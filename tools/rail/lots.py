"""The railway's two lots as the game reads them, each in its data folder (godot/data/<lot>/, its lot
godot/data/lots/<lot>.json):
- rerB, the RER B line (build_rail.py): its track, earthworks, platforms, structures, signals, catenary, services, the
  yard; massyPalaiseau, Massy-Palaiseau's station (massy_station.py), its bus station and bus depot (bus_station.py,
  bus_depot.py);
- plan.json: its design, its zones among it (the ground it designs: kind, outline, axis...; massyPalaiseau's after
  rerB's: they never take ground from them);
- ground.json and ground.bin: those zones' ground for the game to draw (tools/common/lot_ground.py: heights on grids,
  materials, walls), and its repairs (Massy-Palaiseau's: the map's ground mended where the LiDAR saw a building site);
- drop.json: its changes to the map's world (drops.py: tools/common/world_edits.py has the keys).

build_rail.py designs the railway and writes them (write()). Their ground and drop again from the plans (after a new
map from the pipeline, or a change of the zones' heights or of the drops):

    .venv/Scripts/python.exe -I tools/rail/lots.py           (Linux/macOS: .venv/bin/python; ~1 min)
"""
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))
import railgeo as rg  # noqa: E402
import mapdata as md  # noqa: E402
import lot_ground  # noqa: E402
import world_edits  # noqa: E402
import drops  # noqa: E402

DATA = md.ROOT / "godot" / "data"
RER, MASSY = "rerB", "massyPalaiseau"
BALLAST_COLOUR = "#8c8379"      # toy ballast: rust-stained crushed granite (photos of the station), lightened like the
                                # rest of the palette
# zones designed to meet the map's ground (the earthworks' slopes and landings, the platforms' blends, the repaired
# ground): their edges come onto it up to MEET m apart (a slope's end against a wall or a bridge steps more: walls)
MEETS = ("slope", "landing", "platform_blend", "regrade", "regrade_floor", "regrade_gravel")
MEET = 0.5


def plan_path(lot: str) -> Path:
    return DATA / lot / "plan.json"


def is_massy(z: dict) -> bool:
    """A zone of Massy-Palaiseau's (massy_station.py, bus_station.py): its sources, its repairs, the bus islands."""
    src = str(z.get("source", ""))
    return src.startswith("massy:") or src.startswith("repair:") or z["kind"] == "bus_island"


def split(rail: dict) -> tuple:
    """The railway's design (build_rail.py's, in one) as the two lots' plans: (rerB's, massyPalaiseau's)."""
    rer = {k: v for k, v in rail.items() if k != "massy"}
    rer["zones"] = [z for z in rail["zones"] if not is_massy(z)]
    massy = dict(rail.get("massy", {}))
    massy["zones"] = [z for z in rail["zones"] if is_massy(z)]
    return rer, massy


def joined(rer: dict, massy: dict) -> dict:
    """The two plans as the railway's design in one (split()'s inverse)."""
    rail = dict(rer)
    m = dict(massy)
    rail["zones"] = rer["zones"] + m.pop("zones", [])
    rail["massy"] = m
    return rail


def load() -> dict:
    """The railway's design from the two plans."""
    return joined(md.load_json(plan_path(RER)), md.load_json(plan_path(MASSY)))


def _write_json(path: Path, data) -> None:
    # bytes, not text: on Windows write_text would end it with CRLF (.gitattributes keeps godot/data/*.json LF)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"))


def write(rail: dict, world: dict, plans: bool = True) -> None:
    """Both lots' plans (`plans`), grounds and drops from the railway's design `rail` and the map's own `world`."""
    t0 = time.time()
    rer, massy = split(rail)
    if plans:
        for lot, plan in ((RER, rer), (MASSY, massy)):
            _write_json(plan_path(lot), plan)
    write_grounds(rail, world)
    R, M = drops.make(world, rail)
    world_edits.write(DATA / RER / "drop.json", R, "Lot rerB's changes to the map's world: tools/rail/lots.py "
                      "(drops.py: the trees and props in its way, its fences, Lozere's station building, the canopies "
                      "and huts on its tracks, the buildings over them); keys: tools/common/world_edits.py")
    world_edits.write(DATA / MASSY / "drop.json", M, "Lot massyPalaiseau's changes to the map's world: "
                      "tools/rail/lots.py (drops.py: the bus station's props, fences and kerbs, its fences by the "
                      "tracks, the halls and decks massy_builder.gd draws instead, the bus depot's trees); keys: "
                      "tools/common/world_edits.py")
    print("lots: %s and %s written in %.0f s (rerB drops %s; massyPalaiseau drops %s)" % (
        RER, MASSY, time.time() - t0, {k: len(v) for k, v in R.items() if v},
        {k: len(v) for k, v in M.items() if v}))


def write_grounds(rail: dict, world: dict) -> None:
    """Both lots' ground: their zones' designed heights (railgeo.zone_heights, on the map's own ground mended by
    Massy-Palaiseau's repairs), their materials, walls and edges, the repairs."""
    H = md.Heights(md.BASE, world["terrain"], world["ground_mesh"]["cell"])
    A = rg.Alignment(rail["alignment"])
    H_fix = H
    repairs = rail.get("massy", {}).get("repairs", [])
    if repairs:
        import massy_station as mst
        H_fix = md.Heights.__new__(md.Heights)
        H_fix.__dict__.update({k: v for k, v in H.__dict__.items() if not k.startswith("_nodes")})
        H_fix.data = mst.apply_repairs(H, repairs)
    design = rg.Design(rail["earthworks"], A, H_fix, [z for z in rail["zones"] if "axis" in z])
    if rail.get("yard", {}).get("bed"):
        design.yard_bed = rg.YardBed(rail["yard"])

    def zone(z: dict) -> dict:
        hard = rg.hard_of(z)
        out = {"id": z.get("id") or z["source"], "kind": z["kind"], "material": hard[1] if hard else None,
               "piece": hard[0] if hard else None, "owned": True, "polygons": z["polygons"], "src": z,
               "portals": z.get("portals") or []}
        if z["kind"] in MEETS:
            out["snap"] = MEET
        if z["kind"] == "yard":                 # (the yard's strips step down to their tracks' beds: ballast steps)
            out["wall"] = "ballast"
        return out

    def height(zz: dict, x, y):
        s, u = rg.project(A, x, y)
        return rg.zone_heights(design, zz["src"], s, u, x, y)

    for lot, zs, rps in ((RER, [zone(z) for z in rail["zones"] if not is_massy(z)], []),
                         (MASSY, [zone(z) for z in rail["zones"] if is_massy(z)],
                          [{"id": rp["id"], "ring": rp["ring"], "height": H_fix.sample} for rp in repairs])):
        r = lot_ground.write(DATA / lot, zs, height, rps, palette={"ballast": BALLAST_COLOUR},
                             about="Lot %s's own ground: tools/rail/lots.py (its plan's zones' designed heights, "
                                   "railgeo.zone_heights; tools/common/lot_ground.py)" % lot)
        print("%s ground: %d zones, %d repairs, %d tiles, %.1f MB raw" % (lot, r["zones"], r["repairs"], r["tiles"],
                                                                       r["bytes"] / 1e6))


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    md.ensure_base()
    write(load(), md.load_json(md.BASE / "world.json"), plans=False)


if __name__ == "__main__":
    main()
