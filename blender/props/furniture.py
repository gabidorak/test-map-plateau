"""Furniture: benches, tables, lamps, the bus shelter and pole, bike racks, bollards, shelters, fountains.
Front = -Y, origin on the ground (see toylib)."""
import math

from toylib import Model, arc


def bench_back() -> Model:
    """Campus bench with backrest: wooden slats on two anthracite side frames, 1.8 m."""
    m = Model("bench_back")
    for i, y in enumerate((-0.2, -0.07, 0.06)):
        m.box((1.8, 0.11, 0.04), (0, y, 0.44), "wood", bevel=0.012)
    for z, y in ((0.62, 0.2), (0.78, 0.23)):
        m.box((1.8, 0.04, 0.12), (0, y, z), "wood", bevel=0.012, rot=(-12, 0, 0))
    for x in (-0.72, 0.72):
        m.box((0.06, 0.5, 0.05), (x, -0.03, 0.4), "anthracite", bevel=0.012)
        m.box((0.06, 0.05, 0.42), (x, -0.2, 0.0), "anthracite", base=True, bevel=0.012)
        m.box((0.06, 0.05, 0.88), (x, 0.2, -0.02), "anthracite", base=True, bevel=0.012, rot=(-10, 0, 0))
        m.box((0.06, 0.5, 0.04), (x, 0.0, 0.02), "anthracite", bevel=0.01)
    m.collide_box((1.8, 0.5, 0.48), (0, 0, 0), base=True).collide_box((1.8, 0.12, 0.45), (0, 0.22, 0.48), base=True)
    return m


def bench_flat() -> Model:
    """Bench without backrest: five slats on two rounded concrete feet."""
    m = Model("bench_flat")
    for y in (-0.18, -0.09, 0.0, 0.09, 0.18):
        m.box((1.8, 0.075, 0.045), (0, y, 0.43), "wood", bevel=0.012)
    for x in (-0.65, 0.65):
        m.box((0.16, 0.42, 0.41), (x, 0, 0), "concrete", base=True, bevel=0.04, seg=3)
    m.collide_box((1.8, 0.45, 0.46), (0, 0, 0), base=True)
    return m


def picnic_table() -> Model:
    m = Model("picnic_table")
    for y in (-0.27, -0.09, 0.09, 0.27):
        m.box((1.8, 0.16, 0.045), (0, y, 0.74), "wood", bevel=0.012)
    for side in (-1, 1):
        for y in (0.62, 0.78):
            m.box((1.8, 0.14, 0.045), (0, side * y, 0.44), "wood", bevel=0.012)
        for x in (-0.6, 0.6):
            m.box((0.07, 0.07, 0.8), (x, side * 0.32, -0.02), "wood_dark", base=True, rot=(side * -22, 0, 0), bevel=0.01)
    for x in (-0.6, 0.6):
        m.box((0.06, 1.75, 0.07), (x, 0, 0.4), "wood_dark", bevel=0.01)
    m.collide_box((1.8, 1.8, 0.78), (0, 0, 0), base=True)
    return m


def lamp_street() -> Model:
    """Campus LED street lamp: tapered anthracite pole 6.5 m, a short arm and a flat luminaire over the road."""
    m = Model("lamp_street", view_range=400.0)
    m.cyl(0.13, 0.45, (0, 0, 0), "anthracite", bevel=0.03)
    m.cyl(0.075, 6.3, (0, 0, 0.4), "anthracite", r2=0.045, sides=14, bevel=0.0)
    m.tube([(0, 0, 6.2), (0, -0.05, 6.55), (0, -0.35, 6.75), (0, -0.85, 6.78)], 0.04, "anthracite", sides=8)
    m.box((0.32, 0.62, 0.09), (0, -1.08, 6.76), "anthracite", bevel=0.03, seg=3, rot=(4, 0, 0))
    m.box((0.24, 0.5, 0.02), (0, -1.1, 6.7), "glow", "glow", bevel=0.008, rot=(4, 0, 0))
    m.collide_cyl(0.11, 3.0)
    return m


def lamp_path() -> Model:
    """Path lamp: slim post 3.6 m with a round diffuser and cap."""
    m = Model("lamp_path", view_range=300.0)
    m.cyl(0.09, 0.3, (0, 0, 0), "anthracite", bevel=0.02)
    m.cyl(0.05, 3.3, (0, 0, 0.25), "anthracite", r2=0.04, sides=12, bevel=0.0)
    m.cyl(0.07, 0.06, (0, 0, 3.5), "anthracite", bevel=0.01)
    m.cyl(0.17, 0.26, (0, 0, 3.55), "glow", "glow", sides=20, bevel=0.03)
    m.cyl(0.22, 0.06, (0, 0, 3.8), "anthracite", r2=0.12, sides=20, bevel=0.02)
    m.collide_cyl(0.08, 3.0)
    return m


def bus_shelter() -> Model:
    """Glass bus shelter 4 x 1.5 m, open towards the road (front): back glass wall, glass side, lit ad panel at
    the upstream end, bench, cantilevered roof with a fascia for the stop name (anchor `fascia`)."""
    L, D = 4.0, 1.5
    m = Model("bus_shelter", view_range=400.0)
    back = D / 2 - 0.1
    for x in (-L / 2 + 0.05, 0.0, L / 2 - 0.05):
        m.box((0.08, 0.08, 2.4), (x, back, 0), "anthracite", base=True, bevel=0.015)
    m.box((L - 0.1, 0.025, 2.0), (0, back, 0.25), "glass", "glass", base=True, bevel=0.0)
    m.box((L - 0.1, 0.05, 0.06), (0, back, 0.22), "anthracite", bevel=0.01)
    m.box((0.025, D - 0.35, 2.0), (L / 2 - 0.05, 0.1, 0.25), "glass", "glass", base=True, bevel=0.0)
    m.box((0.08, 0.08, 2.4), (L / 2 - 0.05, -D / 2 + 0.2, 0), "anthracite", base=True, bevel=0.015)
    # ad panel ("mupi") closing the upstream side: white frame, lit poster both faces
    m.box((0.16, 1.2, 1.85), (-L / 2 + 0.05, 0.05, 0.2), "white", base=True, bevel=0.03)
    for s in (-1, 1):
        m.box((0.01, 1.04, 1.62), (-L / 2 + 0.05 + s * 0.082, 0.05, 0.31), "glow", "glow", base=True, bevel=0.0)
    m.box((0.1, 0.1, 0.2), (-L / 2 + 0.05, 0.05, 0.0), "anthracite", base=True)
    # roof: slab, rounded fascia at the front
    m.box((L + 0.3, D + 0.2, 0.1), (0, 0.05, 2.42), "anthracite", base=True, bevel=0.035, seg=3)
    m.box((L + 0.3, 0.07, 0.24), (0, -D / 2 - 0.04, 2.32), "white", base=True, bevel=0.025, seg=3)
    m.box((L + 0.28, D, 0.02), (0, 0.05, 2.41), "glass", "glass", base=True, bevel=0.0)
    m.anchor("fascia", x=0.0, y=-D / 2 - 0.08, z=2.44, w=L, h=0.2)
    # timetable panel on the back glass, bench
    m.box((0.7, 0.03, 0.9), (1.0, back - 0.03, 1.1), "white", base=True, bevel=0.01)
    m.box((0.6, 0.01, 0.12), (1.0, back - 0.05, 1.86), "idfm_blue", base=True, bevel=0.0)
    m.anchor("timetable", x=1.0, y=back - 0.06, z=1.55, w=0.6, h=0.5)
    m.box((1.7, 0.36, 0.05), (0.15, back - 0.25, 0.46), "steel", bevel=0.015)
    for x in (-0.6, 0.9):
        m.box((0.05, 0.3, 0.05), (x, back - 0.2, 0.43), "anthracite", bevel=0.01)
    m.collide_box((L, 0.12, 2.4), (0, back, 0), base=True)
    m.collide_box((0.12, D - 0.3, 2.4), (L / 2 - 0.05, 0.1, 0), base=True)
    m.collide_box((0.2, 1.2, 2.1), (-L / 2 + 0.05, 0.05, 0), base=True)
    m.collide_box((1.7, 0.4, 0.48), (0.15, back - 0.25, 0), base=True)
    m.info["shelter_size"] = [L, D]
    return m


def bus_pole() -> Model:
    """IDFM bus stop pole: steel post with a flag (white board, blue band) beside it; the Godot builder writes
    the stop name on the band and the line badges below (anchor `flag`, faces +-Y)."""
    m = Model("bus_pole", view_range=250.0)
    m.cyl(0.08, 0.1, (0, 0, 0), "anthracite", bevel=0.02)
    m.cyl(0.04, 3.0, (0, 0, 0.05), "steel", sides=12, bevel=0.0)
    m.cyl(0.05, 0.05, (0, 0, 3.03), "anthracite", bevel=0.015)
    w, h, z0 = 0.5, 0.82, 2.05
    m.box((w, 0.035, h), (0.04 + w / 2, 0, z0), "white", base=True, bevel=0.015)
    m.box((w + 0.01, 0.04, 0.17), (0.04 + w / 2, 0, z0 + h - 0.17), "idfm_blue", base=True, bevel=0.012)
    for z in (z0 + 0.1, z0 + h - 0.1):
        m.box((0.08, 0.05, 0.05), (0.04, 0, z), "anthracite", bevel=0.01)
    m.anchor("flag", x=0.04 + w / 2, z0=z0, w=w, h=h, band=0.17, t=0.0225)
    m.collide_cyl(0.06, 3.0)
    return m


def bike_rack() -> Model:
    """Sheffield stand: one steel hoop, its plane along the front (bikes lean on both sides)."""
    m = Model("bike_rack")
    r = 0.18
    pts = [(0, -0.38, -0.05), (0, -0.38, 0.8 - r)] + [(0, y, z) for y, z in arc(-0.38 + r, 0.8 - r, r, 180, 90, 6)][1:] + \
          [(0, y, z) for y, z in arc(0.38 - r, 0.8 - r, r, 90, 0, 6)] + [(0, 0.38, -0.05)]
    m.tube(pts, 0.03, "steel", sides=10)
    m.collide_box((0.08, 0.8, 0.8), (0, 0, 0), base=True)
    return m


def bike_loops() -> Model:
    """Wall loop for one or two bikes: a steel half-ring sticking out of the wall at wheel height."""
    m = Model("bike_loops", wall=True)
    pts = [(0, 0.0, 0.75), (0, -0.12, 0.75)] + [(0, -0.12 - 0.2 * math.sin(math.radians(a)), 0.55 + 0.2 * math.cos(math.radians(a)))
                                                for a in range(20, 180, 20)] + [(0, -0.12, 0.35), (0, 0.0, 0.35)]
    m.tube(pts, 0.022, "steel", sides=8)
    for z in (0.75, 0.35):
        m.box((0.08, 0.02, 0.08), (0, -0.01, z), "anthracite", bevel=0.005)
    m.collide_box((0.06, 0.35, 0.45), (0, -0.17, 0.33), base=True)
    return m


def bike_shelter() -> Model:
    """Covered bike stands: curved roof on two posts over five hoops, 4 m long (stretched to the capacity)."""
    m = Model("bike_shelter", view_range=250.0)
    L = 4.0
    for x in (-L / 2 + 0.1, L / 2 - 0.1):
        m.box((0.1, 0.1, 2.2), (x, 0.8, 0), "anthracite", base=True, bevel=0.015)
        m.tube([(x, 0.8, 2.15)] + [(x, 0.8 - 1.0 + 1.0 * math.cos(math.radians(a)), 2.15 + 0.35 * math.sin(math.radians(a)))
                                   for a in range(0, 181, 30)][1:], 0.04, "anthracite", sides=8)
    for i in range(6):
        a0, a1 = math.radians(i * 30), math.radians((i + 1) * 30)
        y = 0.8 - 1.0 + 1.0 * (math.cos(a0) + math.cos(a1)) / 2
        z = 2.15 + 0.35 * (math.sin(a0) + math.sin(a1)) / 2 + 0.04
        tilt = math.degrees(math.atan2(0.35 * (math.sin(a1) - math.sin(a0)), 1.0 * (math.cos(a1) - math.cos(a0))))
        m.box((L + 0.2, 0.38, 0.03), (0, y, z), "glass", "glass", rot=(180 - tilt, 0, 0), bevel=0.0)
    for k in range(5):
        x = -L / 2 + 0.4 + k * (L - 0.8) / 4
        r = 0.18
        pts = [(x, -0.3, -0.05), (x, -0.3, 0.8 - r)] + [(x, y, z) for y, z in arc(-0.3 + r, 0.8 - r, r, 180, 90, 5)][1:] + \
              [(x, y, z) for y, z in arc(0.4 - r, 0.8 - r, r, 90, 0, 5)] + [(x, 0.4, -0.05)]
        m.tube(pts, 0.028, "steel", sides=8)
    for x in (-L / 2 + 0.1, L / 2 - 0.1):
        m.collide_box((0.12, 0.12, 2.2), (x, 0.8, 0), base=True)
    return m


def bollard() -> Model:
    m = Model("bollard", view_range=120.0)
    m.cyl(0.085, 0.72, (0, 0, -0.02), "anthracite", sides=14, bevel=0.0)
    m.sphere(0.085, (0, 0, 0.7), "anthracite", seg=14, scale=(1, 1, 0.75))
    m.cyl(0.088, 0.05, (0, 0, 0.56), "white", sides=14, bevel=0.005)
    m.collide_cyl(0.1, 0.8)
    return m


def concrete_block() -> Model:
    m = Model("concrete_block", view_range=150.0)
    m.box((1.0, 0.6, 0.6), (0, 0, 0), "concrete", base=True, bevel=0.05, seg=3)
    m.collide_box((1.0, 0.6, 0.6), (0, 0, 0), base=True)
    return m


def jersey_barrier() -> Model:
    m = Model("jersey_barrier", view_range=150.0)
    prof = [(-0.3, 0.0), (0.3, 0.0), (0.3, 0.08), (0.12, 0.28), (0.08, 0.8), (-0.08, 0.8), (-0.12, 0.28), (-0.3, 0.08)]
    m.plate(prof, 2.0, (-1.0, 0, 0), "concrete", rot=(0, 0, -90), bevel=0.02)
    for x in (-0.6, 0.6):
        m.box((0.3, 0.17, 0.12), (x, -0.105, 0.55), "sign_red", bevel=0.01, rot=(-8, 0, 0))
    m.collide_box((2.0, 0.6, 0.8), (0, 0, 0), base=True)
    return m


def shelter_canopy() -> Model:
    """Small open shelter 4 x 3 m (stretched to the OSM area): four posts and a wooden roof."""
    m = Model("shelter_canopy", view_range=300.0)
    for x in (-1.85, 1.85):
        for y in (-1.35, 1.35):
            m.box((0.14, 0.14, 2.5), (x, y, 0), "wood_dark", base=True, bevel=0.02)
            m.collide_box((0.16, 0.16, 2.5), (x, y, 0), base=True)
    m.box((4.3, 3.3, 0.14), (0, 0, 2.5), "wood", base=True, bevel=0.04, seg=3)
    m.box((4.0, 0.1, 0.18), (0, -1.35, 2.35), "wood_dark", base=True, bevel=0.02)
    m.box((4.0, 0.1, 0.18), (0, 1.35, 2.35), "wood_dark", base=True, bevel=0.02)
    return m


def fitness_bars() -> Model:
    m = Model("fitness_bars")
    for i, (x, h) in enumerate(((-1.2, 1.2), (0.0, 1.8), (1.2, 2.3))):
        for dx in (-0.5, 0.5):
            m.cyl(0.05, h, (x + dx, 0, 0), "sign_green", sides=12, bevel=0.01)
            m.collide_cyl(0.07, h, (x + dx, 0, 0))
        m.tube([(x - 0.5, 0, h - 0.04), (x + 0.5, 0, h - 0.04)], 0.025, "steel")
    return m


def artwork() -> Model:
    """A cheerful abstract sculpture on a plinth (stand-in for any OSM artwork)."""
    m = Model("artwork", view_range=300.0)
    m.box((1.2, 1.2, 0.5), (0, 0, 0), "concrete", base=True, bevel=0.04, seg=3)
    m.sphere(0.45, (0, 0, 0.95), "sign_red", seg=20)
    m.tube([(0.0 + 0.55 * math.cos(math.radians(a)), 0.55 * math.sin(math.radians(a)) * 0.3, 1.6 + 0.55 * math.sin(math.radians(a)))
            for a in range(0, 361, 20)], 0.08, "sign_yellow", sides=10)
    m.sphere(0.22, (0.3, -0.2, 2.35), "sign_blue", seg=16)
    m.collide_box((1.2, 1.2, 1.5), (0, 0, 0), base=True)
    return m


def fountain() -> Model:
    """Round basin with a centre column (amenity=fountain)."""
    m = Model("fountain", view_range=300.0)
    m.cyl(1.25, 0.45, (0, 0, 0), "stone", sides=40, bevel=0.06, seg=3)
    m.cyl(1.08, 0.02, (0, 0, 0.36), "glass", "glass", sides=40, bevel=0.0)
    m.cyl(0.15, 0.9, (0, 0, 0.3), "stone", sides=16, bevel=0.02)
    m.cyl(0.45, 0.12, (0, 0, 1.15), "stone", r2=0.5, sides=24, bevel=0.03)
    m.sphere(0.12, (0, 0, 1.35), "glass", "glass", seg=12)
    m.collide_cyl(1.25, 0.5)
    return m


def drinking_fountain() -> Model:
    m = Model("drinking_fountain")
    m.box((0.3, 0.3, 0.95), (0, 0, 0), "anthracite", base=True, bevel=0.04, seg=3)
    m.cyl(0.2, 0.08, (0, -0.05, 0.95), "steel", sides=20, bevel=0.02)
    m.tube([(0, 0.05, 1.0), (0, 0.0, 1.12), (0, -0.08, 1.1)], 0.015, "steel")
    m.collide_box((0.32, 0.32, 1.0), (0, 0, 0), base=True)
    return m


def water_tap() -> Model:
    m = Model("water_tap", view_range=100.0)
    m.box((0.14, 0.14, 0.9), (0, 0, 0), "anthracite", base=True, bevel=0.03)
    m.tube([(0, 0, 0.78), (0, -0.12, 0.78), (0, -0.15, 0.72)], 0.02, "steel")
    m.cyl(0.03, 0.04, (0, 0, 0.9), "steel", bevel=0.01)
    m.collide_cyl(0.1, 0.9)
    return m


MODELS = {f.__name__: f for f in (bench_back, bench_flat, picnic_table, lamp_street, lamp_path, bus_shelter, bus_pole,
                                  bike_rack, bike_loops, bike_shelter, bollard, concrete_block, jersey_barrier,
                                  shelter_canopy, fitness_bars, artwork, fountain, drinking_fountain, water_tap)}
