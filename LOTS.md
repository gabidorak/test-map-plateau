# Lots

Every change made to the map (a building replaced, a garden redone, a villa built) is a **lot**:
`godot/data/lots/<id>.json` ties its three phases together, and `godot/scripts/builder/lots.gd` runs them in order.

| Phase | When | A lot's key | Where |
|---|---|---|---|
| 1. Terraforming | right after the map is read, when it is built | `terraform`: files of `godot/data/terraform/`, or a script whose `terraform_zones()` makes them from its design | `scripts/builder/terraform.gd` (file zones made by `tools/terraform.py`; the villa's court from `villaEnPierreCoteaux_data.gd`) |
| 2. Removal | when the map is built | `drop`: its changes to the map's world as its tool decided them (`godot/data/<lot>/drop.json`), then `script`: its `drop(world)` | `scripts/builder/world_edits.gd` (its keys: `tools/common/world_edits.py`), the lot's script |
| 2a. Own ground | when the map is built | `ground`: `godot/data/<lot>/` (`ground.json`, `ground.bin`), or its script's `ground_owned()` | `scripts/builder/lot_ground.gd` (made with `tools/common/lot_ground.py`), `scripts/builder/ground_cut.gd` |
| 2b. Ground paint | when the map is built | `paint`: a script's `repaint()` | the lot's data script |
| 2c. Ground surfaces | when the map is built | its script's `surface_boxes()`, `surface_at()` | `scripts/builder/ground_bake.gd` |
| 3. Building | in the game | `node` (game.gd's member), `restyle` (specs of `godot/data/restyle/`) | the lot's script, `scripts/restyle/` |

A terraforming file or a restyled building's spec counts only when a lot names it. Lots today: `rerB`, `massyPalaiseau` (the railway's,
below), `logementsX`, `losplatos`,
`allSuites`, `villaEnPierreCoteaux`, `ensae`, `campusEdf`, `ilot-001`, `superette258`, `baseNautique` (the boat hire
on the Lac de l'X: its counter is PTA Online's terminal, `godot/scripts/online/boat_hire.gd`), `residenceHaignere`
(the grounds round the Haigneré residence, #536 kept: `godot/scripts/residenceHaignere/`, its plan made of a few
lines with Godot's polygon tools: the bands along the roads offset from their kerb, the alley off the facade),
`ligne18` and its children `ligne18-viaduc`, `ligne18-polytechnique`, `ligne18-universite` (line 18, below).

The ground the game reads (`scripts/ground_map.gd`: the grass, the bots, the picker, every height in the game) is
baked when the map is built (`scripts/builder/ground_bake.gd`, into `godot/scenes/generated/ground.json` and its two
files): the map's own ground with the lots' terraforming in its heights and their surfaces among its pieces. A lot
gives its surfaces with `surface_boxes()` (where) and `surface_at(x, y, current)` (the material there, "" for the
map's): its roads asphalt, its sidewalks and forecourts paving, its lawns grass. Nothing of a lot's ground runs in the
game; like its terraforming, a change to it needs the map rebuilt.

A lot is **in progress** or **finished** (`"finished": true`). In progress, its node builds it at start in the game,
so a change to its building needs no map rebuilt (its ground, terraforming and removals do). Finished, it is built
into the map when the map is built (`scripts/builder/lot_bake.gd`): its node's builds and its restyled buildings are
saved in the generated scene under `Lots/<id>`, streamed with the map's buildings (their far shapes made then), and in
the game its node takes them back (`Lots.baked()`) and only brings them to life (a door, a terminal). Finished:
`losplatos`, `baseNautique`, `ensae`, `campusEdf`, and the railway's lots (below). To work on a finished lot again:
drop its `"finished"`.

A lot may be part of another (`"parent"`): a block's own lot (`ilot-NNN`, a generic name and a number) and the lots
in that block. A child comes after its parent; its terraforming is laid on its parent's (the zones are applied one on
the other, in the lots' order), only where the parent's script's `child_weight(x, y)` lets it (for a block: inside its
sidewalks, never under its streets, which are drawn on the block's plan). A child with no terraforming just adds to
the block. To redo a building of a block with its ground: a lot with `"parent": "ilot-NNN"`, its zones, and the
building out of the plan's `KEPT`.

A whole block redone (the 25/8 supermarket's): one master plan, `godot/scripts/ilot/ilot_plan.gd`, drawn in the
block's streets' frame (the map turned so they run straight), that its lots share: `ilot-001`, the block's own lot and the parent of the others (the ground's
terraforming from the plan's `terraform_zones()`, the ring of roads and sidewalks round the block, its greenery and
furniture; `scripts/street_kit.gd`, the street kit any lot's plan can use, draws streets: asphalt, setts, granite
kerbs, sidewalks lowered at accesses, markings)
then its children `superette258` (the shop, its yard, the filling station, the car park: `scripts/superette/`) and
`losplatos` (Losplatos Custom, set square to its street, its front sidewalk the block's).

Line 18 of the Grand Paris Express (ref/metro18/, research): one master plan its lots share, frozen,
`godot/data/ligne18/plan.json` (read by `godot/scripts/ligne18/ligne18_plan.gd`, made by `tools/ligne18/build_plan.py`
from OSM and the map's ground; a rerun keeps the piers where they are, moving only those in the AI's car and bus
lanes). It holds the axis, straight through the stations; the rails' profile (stations level, 3 % at most); the
piers' places, clear of the roads and lanes; and each station's frame and levels. `ligne18` is the line's own lot
(no node), the parent of:
- `ligne18-viaduc`: the ramp, the deck and its parapets outside the stations, the piers, and the tracks along the
  whole line, through the stations too. It is cut into cells of ~200 m with far shapes of its own.
- `ligne18-polytechnique` and `ligne18-universite`: each station over its zone (u -45..45 along the line: its deck
  under the tracks, the platforms, the building, the supports the viaduct's first spans rest on), and its grounds up
  to the roads round it.
The decks meet face to face at the zones' ends with the plan's `section()`. Tests: `godot/tools/test_ligne18_*.gd`.
Christ de Saclay and the line east of the ramp (at grade, the tunnel to Massy) wait for the map to be extended.

What a lot builds in the game is streamed like the map's buildings (`godot/scripts/builder/lot_far.gd`, called by
`Lots.spawn`): each of its buildings (its node's children) is a cell of `world_streamer.gd`, in full detail within
180 m of the camera, beyond that its far shape (`godot/scripts/builder/far_proxy.gd`, as for the map's buildings: its
form without its details), without shadows. Nothing to do per building; a node whose visibility its lot runs itself (a door's slats) goes in the group `lot_own_visibility`.

A new building or garden: make its terraforming zones (`tools/terraform.py zone ...`), its spec or script, then a lot
that names them; rebuild the map (`godot/tools/build_world.gd`).

## A lot's own ground

Terraforming reshapes the map's ground as a height field: it cannot step. A lot whose ground steps (a trench, a
stairwell, a platform, a raised quay or sidewalk) owns its ground there: the map's ground mesh is cut out along its
polygons (`scripts/builder/ground_cut.gd`: the triangles inside out, those across the outline cut, the rest exactly as
they were), the terrain's collision holed over them, and the lot draws and collides its own. A lot's tool designs it
(`tools/common/lot_ground.py`: its zones, each with its heights on 1 m grids, its material, the ground piece the game
reads there, the material of its walls; its repairs, the map's ground mended round it) into `godot/data/<lot>/ground.*`,
and `scripts/builder/lot_ground.gd` lays it into the map when the map is built: the heights stamped into the
heightmap, the materials into the ground the game reads, the zones drawn in 2 m squares with a wall wherever a zone
meets another ground higher or lower (its 2 m cells cliffs: no grass), or its edge brought onto the map's ground where
it is designed to meet it (`snap`). Nothing of the design is computed again in Godot.

## The railway's lots

The RER B line (`rerB`) and Massy-Palaiseau's station with its bus station and bus depot (`massyPalaiseau`) are lots
with no node: their `"build"` is a builder run when the map is built, with the map's own builds
(`builder/rail_builder.gd`, `massy_builder.gd` with `hangar_builder.gd`: `Lots.build()`, in the lots' order), so they
are always finished. One tool designs both, `tools/rail/` (they are designed together: the line's zones first,
Massy-Palaiseau's after them; the trees, props and fences of both), and `tools/rail/lots.py` writes each lot's folder:
- `plan.json`: its design, its zones among it (`godot/data/rerB/plan.json`: the alignment, profile, earthworks,
  platforms, structures, signals, catenary, services, the yard: `build_rail.py`; `godot/data/massyPalaiseau/plan.json`:
  the footbridges, halls, line 18 box, bus station and depot: `massy_station.py`, `bus_station.py`, `bus_depot.py`);
- `ground.json`, `ground.bin`: its own ground (the trackbed, platforms, slopes, stairwells, the road's trench, the
  yard; the bus station's islands, the line 18 shaft, Massy-Palaiseau's repaired ground), the zones' designed heights
  (`railgeo.zone_heights`);
- `drop.json`: its changes to the map's world (`tools/rail/drops.py`: the trees and props in the line's way, its
  fences, Lozère's station building, the canopies and huts on its tracks, the buildings over them; the bus station's
  props, fences and kerbs, the halls and decks `massy_builder.gd` draws instead, the bus depot's trees).
The game reads the plans (the builders, the trains: `rail_map.gd`, `train_traffic.gd`, `loading_map.gd`). A change:
`tools/rail/build_rail.py` (all of it again, ~1 min) or `tools/rail/lots.py` (ground and drops from the plans), then
the map rebuilt. `tools/rail/patch_world.py` still patches the map's own files with the railway's ground, under the
lots' own ground; it goes with `godot/world/base/`.

The Logements de l'X (`logementsX`) were laid out by the same tools once; they are a lot like any other now: their
plan `godot/data/logementsX/plan.json` and their `drop.json` (`tools/logements_x/build_plan.py` from the map's own
ground: the construction site out, their trees, props, the plan's buildings in), their terraforming (the site's
smooth ground), own ground (the boulevard's raised sidewalk), surfaces and paint in `scripts/logementsX/`, and their
`"build"` drawing the facades and the surfaces themselves (the road fill, the car park, paths, the raised sidewalk) in
the ground's material.
