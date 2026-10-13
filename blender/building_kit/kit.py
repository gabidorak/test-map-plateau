"""Building kit (milestone M7): the facade and roof details that matter in silhouette, placed by
pipeline/plateau/facades.py and drawn by the Godot building builder with one MultiMesh per module and chunk.
Unit sizes, stretched per instance (scale = width, depth, height): keep the parts simple so stretching reads well.
Model space as in toylib: metres, z up, front = -Y. Wall modules have their back on the wall plane y = 0 and the
origin at floor level; roof modules stand on the deck. `tint` parts take the building's accent colour."""
from toylib import Model, circle


def balcony() -> Model:
    """Balcony 1 m wide, 1 m deep: rounded slab with a glass railing on a tinted frame."""
    m = Model("balcony", wall=True, view_range=260.0)
    m.box((1.0, 1.0, 0.16), (0, -0.5, -0.16), "#eeeae2", base=True, bevel=0.05, seg=3)
    m.box((0.98, 0.03, 0.82), (0, -0.96, 0.08), "glass", "glass", base=True, bevel=0.0)
    for x in (-0.48, 0.48):
        m.box((0.03, 0.94, 0.82), (x, -0.5, 0.08), "glass", "glass", base=True, bevel=0.0)
    m.box((1.0, 0.06, 0.05), (0, -0.97, 0.98), "white", "tint", bevel=0.02)
    for x in (-0.49, 0.49):
        m.box((0.05, 0.98, 0.05), (x, -0.5, 0.98), "white", "tint", bevel=0.02)
        m.box((0.05, 0.05, 0.9), (x, -0.97, 0.0), "white", "tint", base=True, bevel=0.015)
    return m


def loggia_railing() -> Model:
    """Railing across a loggia opening, flush with the facade."""
    m = Model("loggia_railing", wall=True, view_range=220.0)
    m.box((1.0, 0.03, 0.85), (0, -0.06, 0.05), "glass", "glass", base=True, bevel=0.0)
    m.box((1.0, 0.07, 0.05), (0, -0.06, 0.98), "white", "tint", bevel=0.02)
    m.box((1.0, 0.1, 0.06), (0, -0.05, 0.0), "white", "tint", base=True, bevel=0.02)
    return m


def slat() -> Model:
    """Vertical brise-soleil fin, 1 m tall (stretched to the facade height), standing 5 cm off the wall."""
    m = Model("slat", wall=True, view_range=320.0)
    m.box((0.07, 0.42, 1.0), (0, -0.27, 0.0), "white", "tint", base=True, bevel=0.025, seg=2)
    return m


def fin() -> Model:
    """Landmark fin or floor ledge (M9): a unit box with its back on the wall, stretched per instance
    (width, depth out of the wall, height). Tinted, so it takes the fin colour of the spec."""
    m = Model("fin", wall=True, view_range=420.0)
    m.box((1.0, 1.0, 1.0), (0, -0.5, 0.0), "white", "tint", base=True, bevel=0.03, seg=2)
    return m


def entrance_canopy() -> Model:
    """Entrance canopy: cantilevered slab 3.2 x 1.8 m with a tinted fascia, hung on two rods."""
    m = Model("entrance_canopy", wall=True, view_range=300.0)
    m.box((3.2, 1.8, 0.2), (0, -0.9, 0.0), "#f1eee8", base=True, bevel=0.06, seg=3)
    m.box((3.26, 0.08, 0.26), (0, -1.81, -0.02), "white", "tint", base=True, bevel=0.03)
    for x in (-1.3, 1.3):
        m.box((0.08, 1.86, 0.26), (x * 1.23, -0.92, -0.02), "white", "tint", base=True, bevel=0.03)
        m.tube([(x, -1.7, 0.2), (x, -0.02, 1.5)], 0.022, "steel", sides=8)
    for x in (-0.8, 0.0, 0.8):
        m.cyl(0.07, 0.02, (x, -0.9, -0.01), "glow", "glow", sides=12, bevel=0.0)
    return m


def piloti() -> Model:
    """Round column 1 m tall (stretched to the slab), r = 0.22 m, with a soft base ring."""
    m = Model("piloti", view_range=400.0)
    m.cyl(0.22, 1.0, (0, 0, 0), "#e9e5dc", sides=20, bevel=0.0)
    m.cyl(0.26, 0.04, (0, 0, 0.0), "#d4d0c6", sides=20, bevel=0.015)
    return m


def roof_railing() -> Model:
    """Rooftop guard rail, 1 m long (stretched), posts at both ends."""
    m = Model("roof_railing", view_range=260.0)
    for z in (0.5, 1.02):
        m.box((1.0, 0.04, 0.04), (0, 0, z), "steel", bevel=0.012)
    for x in (-0.48, 0.48):
        m.box((0.04, 0.04, 1.06), (x, 0, 0.0), "steel", base=True, bevel=0.012)
    return m


def roof_unit() -> Model:
    """AC unit / small plant box 1 x 1 x 1 m with a fan grille on top."""
    m = Model("roof_unit", view_range=300.0)
    m.box((1.0, 1.0, 1.0), (0, 0, 0), "silver", base=True, bevel=0.06, seg=3)
    m.cyl(0.3, 0.03, (0, 0, 0.99), "dark", sides=20, bevel=0.0)
    m.cyl(0.08, 0.05, (0, 0, 1.0), "steel", sides=12, bevel=0.0)
    for z in (0.25, 0.45, 0.65):
        m.box((0.8, 0.02, 0.05), (0, -0.505, z), "steel", bevel=0.0)
    return m


def solar_panel() -> Model:
    """Row of photovoltaic panels 1 m long (stretched), 1 m deep, tilted towards the front (south) on low legs."""
    m = Model("solar_panel", view_range=260.0)
    m.box((1.0, 1.04, 0.04), (0, 0, 0.3), "#24366b", rot=(15, 0, 0), bevel=0.01)
    for y in (-0.26, 0.0, 0.26):
        m.box((0.98, 0.012, 0.012), (0, y * 0.966, 0.3 + 0.025 + y * 0.259), "#7f93c4", rot=(15, 0, 0), bevel=0.0)
    for x in (-0.42, 0.42):
        m.box((0.04, 0.04, 0.2), (x, -0.42, 0.0), "steel", base=True, bevel=0.0)
        m.box((0.04, 0.04, 0.42), (x, 0.42, 0.0), "steel", base=True, bevel=0.0)
    return m


MODELS = {f.__name__: f for f in (balcony, loggia_railing, slat, fin, entrance_canopy, piloti, roof_railing, roof_unit, solar_panel)}
