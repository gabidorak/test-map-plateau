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
`allSuites`, `villaEnPierreCoteaux`, `ensae`, `campusEdf`.

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
