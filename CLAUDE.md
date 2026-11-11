# Plateau map: notes for contributors (and Claude Code)

## Map data is not in git

The generated map (`godot/world/` heightmaps, ground and `world.json`, `godot/world/base/`,
`godot/scenes/generated/neighborhood.tscn` and `meshes/`) is git-ignored. It lives on the `map-data` GitHub prerelease,
and `map_data.lock` pins the version each commit uses. Details: "Map data (not in git)" in [README.md](README.md).

- **After rebuilding the map** (pipeline, `patch_world`, `build_world`): run `python3 tools/map_data.py publish` (it
  uploads only the changed shards), then commit `map_data.lock` along with the code. If you forget, the pre-push hook
  blocks the push.
- **After a pull that changes `map_data.lock`**: run `python3 tools/map_data.py fetch`.
- **Once per clone**: `python3 tools/map_data.py fetch` and `python3 tools/map_data.py install-hook`.
- `fetch` never overwrites map edits that were not published (`--force` does). `status` shows how the map here differs
  from `map_data.lock`.
- Never commit the map files themselves, and never push from a clone made before 2026-11-06 (its history still holds
  the old map files).

## Changes to the map are lots

Any building replaced, restyled or added, any garden or ground reworked, is a **lot**: `godot/data/lots/<id>.json`
ties its terraforming (`godot/data/terraform/`, made by `tools/terraform.py`), its removals (its script's `drop()`) and
its building (its node, or its restyled specs in `godot/data/restyle/`), run in that order by
`godot/scripts/builder/lots.gd`. Add a lot rather than hooking a new build into `world_builder.gd`, `ground_builder.gd`
or `game.gd`; ask Thomas the terraforming questions first (is the ground flat? the grass mown? trees, hedges, paths?).
How it works, and the railway's lots still to migrate: [LOTS.md](LOTS.md).

## PTA Online's dev mode (offline test)

PTA Online played solo, without the server or a login: 10 M € (refill in the in-game menu, Esc), every unarmed vehicle
in the garage, the fly camera, shortcuts to the bus depot, the fire station and Prestige Motors.

- From PowerShell (in the repository): `& "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe" --path godot -- --online-test`
- From bash (Git Bash): `GODOT=/c/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe sh godot/tools/online_test.sh`
  (`GODOT`: the Godot binary, default `godot` on the PATH; extra arguments go to the game, e.g. `--name=Tester`;
  `PLATEAU_ONLINE_VEHICLES` (models, comma-separated) and `PLATEAU_ONLINE_MONEY` replace the garage and the money).
- Same thing by hand: `godot --path godot -- --online-test`.
- From the editor: run the game (F5), PTA Online, "Test offline".
- Headless tests use it too: `godot --headless --fixed-fps 60 --path godot --script res://tools/<test>.gd -- --online-test`
  (not every test: `test_fires.gd` runs without it, see its header).
