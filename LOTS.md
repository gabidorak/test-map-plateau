# Lots

Every change made to the map (a building replaced, a garden redone, a villa built) is a **lot**:
`godot/data/lots/<id>.json` ties its three phases together, and `godot/scripts/builder/lots.gd` runs them in order.

| Phase | When | A lot's key | Where |
|---|---|---|---|
| 1. Terraforming | right after the map is read, when it is built | `terraform`: files of `godot/data/terraform/`, or a script whose `terraform_zones()` makes them from its design | `scripts/builder/terraform.gd` (file zones made by `tools/terraform.py`; the villa's court from `villaEnPierreCoteaux_data.gd`) |
| 2. Removal | when the map is built | `script`: its `drop(world)` | the lot's script (`scripts/builder/world_edits.gd` helps) |
| 2b. Ground paint | when the map is built | `paint`: a script's `repaint()` | the lot's data script |
| 3. Building | in the game | `node` (game.gd's member), `restyle` (specs of `godot/data/restyle/`) | the lot's script, `scripts/restyle/` |

A terraforming file or a restyled building's spec counts only when a lot names it. Lots today: `losplatos`,
`allSuites`, `villaEnPierreCoteaux`, `ensae`, `campusEdf`, `ilot-001`, `superette258`.

A lot may be part of another (`"parent"`): a block's own lot (`ilot-NNN`, a generic name and a number) and the lots
in that block. A child comes after its parent; its terraforming is laid on its parent's (the zones are applied one on
the other, in the lots' order), only where the parent's script's `child_weight(x, y)` lets it (for a block: inside its
sidewalks, never under its streets, which are drawn on the block's plan). A child with no terraforming just adds to
the block. To redo a building of a block with its ground: a lot with `"parent": "ilot-NNN"`, its zones, and the
building out of the plan's `KEPT`.

A whole block redone (the 25/8 supermarket's): one master plan, `godot/scripts/ilot/ilot_plan.gd`, drawn in the
block's streets' frame (the map turned so they run straight), that its lots share: `ilot-001`, the block's own lot and the parent of the others (the ground's
terraforming from the plan's `terraform_zones()`, the ring of roads and sidewalks round the block, its greenery and
furniture; `scripts/ilot/urban_kit.gd` draws streets: asphalt, granite kerbs, sidewalks lowered at accesses, markings)
then its children `superette258` (the shop, its yard, the filling station, the car park: `scripts/superette/`) and
`losplatos` (Losplatos Custom, set square to its street, its front sidewalk the block's).

What a lot builds in the game is streamed like the map's buildings (`godot/scripts/builder/lot_far.gd`, called by
`Lots.spawn`): each of its buildings (its node's children) is a cell of `world_streamer.gd`, in full detail within
180 m of the camera, beyond that its far shape (`godot/scripts/builder/far_proxy.gd`, as for the map's buildings: its
form without its details), without shadows. Nothing to do per building; a node whose visibility its lot runs itself (a door's slats) goes in the group `lot_own_visibility`.

A new building or garden: make its terraforming zones (`tools/terraform.py zone ...`), its spec or script, then a lot
that names them; rebuild the map (`godot/tools/build_world.gd`).

## To do: the railway's lots (planned for the week of 2026-11-16)

The RER B line, the Massy-Palaiseau station, the bus depot (the yard) and the Logements de l'X are not lots yet. Their
ground is designed in `godot/world/rail.json` (made by `tools/rail/build_rail.py`, `massy_station.py`,
`bus_depot.py`, `logements_x.py`) and patched into the map's files by `tools/rail/patch_world.py`, which also clears
their trees and props; their buildings are made when the map is built (`rail_builder.gd`, `massy_builder.gd`,
`hangar_builder.gd`, `logements_x_builder.gd`). That designed ground does what `terraform.gd` cannot (walls,
platform edges, a ground mesh cut again, collision holes), so the first step is to declare them as lots pointing at
it, not to rewrite it.

Prompt to give Claude Code (or anyone) then:

> Lis LOTS.md. Déclare le RER B, la gare de Massy-Palaiseau, le dépôt de bus et les Logements de l'X comme des lots
> (godot/data/lots/), sans réécrire leur terrain dessiné : un lot doit pouvoir renvoyer vers les zones de rail.json
> appliquées par tools/rail/patch_world.py et vers son constructeur Godot. Sépare rail.json en un fichier par lot si
> c'est plus clair (la ligne, Massy, le dépôt, les Logements X), en gardant les outils qui le produisent cohérents.
> Vérifie que la carte reconstruite est identique (mêmes comptes de bâtiments, arbres, objets) et que les tests du
> rail et de Massy passent. Pose-moi les questions de terraforming habituelles avant de changer un terrain.
