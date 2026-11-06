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
