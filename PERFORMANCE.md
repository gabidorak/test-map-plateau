# Performance audit

Audit of 2026-10-16, branch `rerb` (commit 41b598f), Godot 4.7.2.

It combines measurements on the dev laptop (Intel Iris Xe and RTX 4050 Laptop, GNOME *performance* and *power-saver* profiles) with a code review of the scripts, builders and shaders. Each number below is labelled **measured** or **est.** (estimated from reading the code). Section 7 explains how to re-run the measurements.

## Summary

1. **The CPU cost of bot traffic is the biggest risk.**
   - In power-saver mode, the real game (`--solo`) runs at **5–7 fps on the Iris Xe and on the RTX 4050 alike**.
   - One physics tick with the default traffic (100 bots + RER B) costs **15.8 ms** in power-saver, which is the whole 60 Hz budget before any rendering. In performance mode it costs 6.7 ms.
   - Godot then runs up to 8 catch-up ticks per frame, and the frame rate collapses (the "spiral of death").
   - The RER B adds 2.5–5 ms per tick on its own, because every train checks every road vehicle each tick.
   - Windows laptops on battery or in "Best power efficiency" mode throttle the CPU the same way, so this is the most likely cause of "unplayable" reports.
2. **On the Iris Xe at 1080p with the Low preset, the game is GPU-bound and misses 60 fps in 9 of the 43 viewpoints.**
   - The worst views run at 51–56 fps: the Télécom courtyard and forecourt, the RER B underpass, cutting and footbridge.
   - The note of 2026-10-10 (before RER B, night mode and the newer buildings) had 61–129 fps.
   - The largest costs are shadows (2–5 ms), the far layer (3–8 ms) and buildings (1–4 ms).
   - The procedural shaders are cheap: 1.3–1.7 ms for all of them together.
   - Lowering the 3D resolution does not help much (FSR at 67 %: −1.2 to −1.9 ms), because the iGPU is limited by geometry: 3.5–5.2 M triangles per frame, counting the shadow passes and the depth prepass.
3. **The High preset on an iGPU-class GPU costs 2.4× more than Low** (42 ms against 18 ms), and 2× MSAA alone accounts for 14–17 ms of that.
   - "Auto" chooses Low only when Vulkan reports an *integrated* GPU. Weak discrete laptop GPUs (the MX series, old GTX cards) get High.
4. **Hitches are not a problem so far.**
   - Driving across the whole map at 90 km/h without traffic, the worst frame was 19 ms (measured).
   - A cold shader cache adds 1.4 s to loading and caused one 45 ms frame in a 60 s drive.
   - The remaining likely hitch sources are vehicle spawns and the first switch to night (est.).

---

## 1. Measurement setup

| | |
|---|---|
| Machine | the dev laptop: Iris Xe (ADL GT2, forced with `VK_ICD_FILENAMES=…/intel_icd.json`), RTX 4050 Laptop, on AC power |
| Render | 1920×1011 window, X11, Vulkan, vsync off; Low preset on the iGPU (auto), High on the RTX (auto) |
| GPU numbers | `godot/tools/_tmp_perfprobe.gd` (temporary, gitignored): the viewpoints of `tools/perf.gd` with GPU time, render CPU time, feature toggles and a drive mode along a bus route. Each figure averages 150 frames after 40 frames of settling. `base` is measured first and last in each run; it drifts < 0.3 ms within a run, but the laptop warms up by ~1.5 ms across runs, so compare numbers within one table only. |
| CPU numbers | `tools/probe_traffic.gd`, headless with `--fixed-fps 60`: real seconds per simulated minute → ms per tick, taken from the second minute (steady state). Plus the real game with `--solo --print-fps`, using a neutral `settings.cfg` (restored afterwards) and a temporary `override.cfg` for project-setting experiments. |
| Not covered | GPU numbers have **no vehicles on screen**: tool runs with bots crash (see 6.1). No Windows machine was available; section 5 is reasoning plus the Linux measurements. |

---

## 2. CPU: bots, trains and the physics spiral

### 2.1 Measured

Cost of one physics tick in ms, headless (no rendering). The budget at 60 Hz is 16.7 ms, and it must also cover rendering and `_process`.

| Traffic | performance | power-saver |
|---|---:|---:|
| none | 0.24 | 0.66 |
| 30 buses | 1.7 | 4.4 |
| 30 buses + RER B | 2.8 | 7.2 |
| 100 bots (30 buses + 70 cars) | 4.2 | 10.6 |
| **100 bots + RER B (default solo game)** | **6.7** | **15.8** |
| same, no bot gliding (`physics` arg: like a LAN game with players spread out) | 11.4 | 27.8 |

The real game, `--solo`, standing at the spawn point, fps over 80–100 s:

| | performance | power-saver |
|---|---:|---:|
| Iris Xe (Low) | ~53 | 5–6 |
| RTX 4050 (High) | ~100 | 6–7 |

Experiments in power-saver (RTX, real game):

| Setting | fps |
|---|---|
| default (`max_physics_steps_per_frame` = 8) | 6 |
| `max_physics_steps_per_frame` = 3 | ~15 |
| `max_physics_steps_per_frame` = 1 | ~35, but the simulation runs at about 0.6× real speed |
| `rendering/driver/threads/thread_model` = Separate | 6 (no change; Godot also warns it is unstable) |

**Why it collapses.** When a frame takes longer than a tick, Godot runs extra physics ticks in the next frame to catch up, up to 8. Each tick costs ~16–20 ms in power-saver, so a frame grows to ~150 ms. The cure is a cheaper tick; the cap on catch-up steps only limits the damage.

### 2.2 Actions (CPU)

Ranked by expected gain. C1 is backed by measurement. C3, C5, C6 and C7 are small changes with no visible tradeoff.

**C1. RER B obstacle scan.**
- **Where:** [train_traffic.gd:207-222](godot/scripts/train_traffic.gd#L207-L222), [train_traffic.gd:271-293](godot/scripts/train_traffic.gd#L271-L293), [rail_map.gd:110](godot/scripts/rail_map.gd#L110).
- **Problem:**
  - Every tick, every running train walks `game.cars` and projects each car onto the rail, even while the train is dwelling at a stop.
  - For a car far from the track, `project()` widens its search three times: 83 dictionary lookups, each allocating an empty `PackedInt32Array`.
- **Measured:** the trains cost 1.1 ms per tick (performance) / 2.8 ms (power-saver) with 30 road vehicles, and 2.5 / 5.2 ms with 100. The cost grows with the number of road vehicles, as this loop predicts.
- **Fix:**
  - Scan only while the train bot is running.
  - Project each vehicle once per tick and share the result between trains.
  - Reject far vehicles in one step, using a dilated bucket set or a bounding box around the line.
  - Optionally throttle the scan to every 0.1–0.2 s.
- **Tradeoff:** none, apart from up to 0.2 s later braking if throttled.
- **Effort:** small.

**C2. Bot gliding distance and traffic density.**
- **Where:** `NEAR = 200 m` in [bus_bot.gd:47](godot/scripts/bus_bot.gd#L47).
- **Measured:** bots that never glide cost 1.7× as much as the default (11.4 against 6.7 ms).
- **Options:**
  - (a) A smaller `NEAR` on Low or on slow CPUs. **Tradeoff:** bots without physics come closer to the player, and since gliders move only every third tick (20 Hz) they could look jerky in view. Interpolating their pose would hide that.
  - (b) A "Traffic: full / reduced / off" setting. `main` already has on/off (commit 2d38119, `Settings.values["traffic"]`, `--no-bots`). "Reduced" could lower `PLATEAU_CARS` (default ~70). **Tradeoff:** emptier streets. In LAN games, the host's choice applies to everyone.
  - (c) Automatic: if the average physics time stays above ~8 ms for 5 s, stow some bot cars.
- **Effort:** small to medium.

**C3. Per-vehicle work that bots don't need.**
- Each vehicle has a SpringArm3D (one shape cast per tick, about 100 per tick in total), built in [car.gd:355](godot/scripts/car.gd#L355). Disable it until the vehicle is driven or ridden.
- Brake lamps call `material_override` every tick, even with no change: [car.gd:949-959](godot/scripts/car.gd#L949-L959), [car.gd:1503](godot/scripts/car.gd#L1503), and for every remote vehicle at [car.gd:1530](godot/scripts/car.gd#L1530). [fire_truck.gd:245](godot/scripts/fire_truck.gd#L245) does the same. Write only on change.
- The steering wheel, hands and arms are written every tick, even for far bots: [car.gd:1551-1567](godot/scripts/car.gd#L1551-L1567).
- **Est.:** 0.5–2 ms per tick with 100 vehicles. **Tradeoff:** none. **Effort:** tiny.

**C4. Bot look-ahead.**
- **Where:** [bus_bot.gd:592-600](godot/scripts/bus_bot.gd#L592-L600), [bus_bot.gd:758-769](godot/scripts/bus_bot.gd#L758-L769).
- **Problem:** for every nearby vehicle, 8 footprint points are projected across the whole look window (50–115 segments each), allocating new arrays every time.
- **Fix:**
  - Reject a vehicle early using its centre projection (behind, beyond reach, too far to the side).
  - Project its footprint only around that centre.
  - Build the footprints once per tick in `traffic._snapshot` rather than once per bot–vehicle pair.
- **Est.:** large in queues at lights and stops.
- **Tradeoff:** keep the margins generous for hairpins.
- **Effort:** medium.

**C5. Per-tick scans of players × vehicles.**
- `game.player_spots()` and `riders()` ([game.gd:602-631](godot/scripts/game.gd#L602-L631)) are called by every bot every tick and allocate each time. Compute them once per physics frame.
- `breakables.gd` collects every vehicle's boxes every tick before skipping the frozen ones ([breakables.gd:110-119](godot/scripts/breakables.gd#L110-L119)). Cache each body's box list and skip stowed or frozen bodies first.
- Remote-player collision checks every car ([remote_player.gd:111-129](godot/scripts/remote_player.gd#L111-L129)). Check only walkable vehicles.
- **Est.:** 0.5–3 ms per tick on a host; more in LAN games. **Effort:** small.

**C6. Standing trains are re-posed every tick.**
- **Where:** [train.gd:343-353](godot/scripts/train.gd#L343-L353).
- **Problem:** that is 30 transform writes per train per tick, each car carrying a hull of about 90 boxes. It happens during the 40 s dwell and at red signals, on every peer.
- **Fix:** skip when `front` and `door_t` are unchanged.
- **Effort:** tiny.

**C7. Articulated-bus bellows.**
- **Where:** [car.gd:695-723](godot/scripts/car.gd#L695-L723).
- **Problem:** the 1 mm threshold is below physics jitter, so moving buses rebuild an ArrayMesh (a new GPU buffer) almost every tick. On clients this applies to every remote articulated bus.
- **Fix:** a threshold of ~1 cm or 0.3°, and skip the rebuild beyond ~100 m.
- **Effort:** tiny.

**C8. A safety net against the spiral.**
- **Fix:** set `physics/common/max_physics_steps_per_frame` to 3.
- **Measured:** 6 → 15 fps when overloaded. No effect when the CPU keeps up.
- **Tradeoff:**
  - When overloaded, the simulation runs slower than real time instead of the frame rate collapsing.
  - Lights and the LAN clock follow real time, so slowed bots drift against them.
  - Remote peers see a slowed host.
- **Effort:** one line. Worth doing in any case, but it does not replace C1–C5.

**C9. Physics interpolation (Godot 4.4+) with fewer ticks for bots.**
- **Idea:** smooth visuals at a lower tick rate, for example by moving gliders at 20 Hz with interpolation.
- **Tradeoff:** VehicleBody3D at 30 Hz would be less stable, so keep 60 Hz for vehicles that players drive.
- **Effort:** medium. Only worth it if C1–C5 are not enough.

**C10. Stowed vehicles keep their engine sound.**
- **Problem:** [car.gd:1444](godot/scripts/car.gd#L1444) returns before `audio.update()`, which is the only place the engine gain fades ([vehicle_audio.gd:177](godot/scripts/vehicle_audio.gd#L177)). A bot stowed near the camera probably keeps humming.
- **Effort:** tiny. This is also a bug (code reading, not heard).

### 2.3 After step 1 (C1, C3, C6, C7, C8, C10), 2026-10-17

What was done:
- **C1:** `rail_map.project()` rejects a point in one lookup when no centreline point is within its search reach (a dilated bucket set). Each vehicle is projected once per tick and shared by every train (`train_traffic._near_line`). The scan runs only for trains in the `run` state.
- **C3:** brake lamps are written only on change. The steering wheel and hands are posed only when the turn changes and within 60 m of the camera. The chase-camera SpringArm3D runs only while the vehicle is driven or ridden. The fire truck's beacons are written only on change.
- **C6:** a train is posed only when `front` changed.
- **C7:** the bellows is rebuilt beyond 8 mm or 0.3°, and only within 100 m of the camera.
- **C8:** `physics/common/max_physics_steps_per_frame=3`.
- **C10:** `VehicleAudio.hush()` on stow.

Measured, before (HEAD 41b598f, in a worktree) and after, run back to back. Probe: ms per tick over minutes 2–3 of `probe_traffic.gd -- 3`.

| | performance | power-saver |
|---|---:|---:|
| 100 bots + RER B (default solo game) | 6.5 → **4.2** | 15.0 → **9.6** |
| 100 bots, no trains | 4.3 → 3.6 | 9.9 → 7.9 |
| real game `--solo`, RTX 4050 (High), fps | ~98 → ~120 | 6 → **20–27** |

The RER B now adds ~0.6 ms per tick (performance), against ~2.2 ms before. In power-saver the tick still uses more than half the 60 Hz budget, so C5, C4 and C2 remain the next levers.

---

## 3. GPU (Iris Xe, Low, 1080p)

### 3.1 Measured

All 43 viewpoints: 8.4–19.6 ms, median 15.1 ms. GPU time is 87 % of the frame on average, and render CPU is at most 1.5 ms.

The table shows the frame-time change in ms when one thing is turned off or changed (negative = faster):

| Change | Télécom forecourt | Tree row | Lozère hillside | Overview (160 m up) | RER B underpass |
|---|---:|---:|---:|---:|---:|
| *base frame time* | *18.1* | *13.5* | *17.4* | *15.4* | *20.8* |
| shadows off | −4.0 | −3.5 | −2.8 | −2.0 | −4.8 |
| shadow atlas 4096 → 2048 | −1.2 | −1.3 | −0.7 | −0.9 | −1.0 |
| 4 → 2 shadow splits | −0.7 | −0.9 | −0.3 | +0.1 | −1.6 |
| shadow distance 250 → 120 m | 0.0 | −0.4 | −0.5 | −0.4 | −0.7 |
| softer shadow filter (very low) | 0.0 | −0.2 | −0.1 | −0.2 | −0.1 |
| no shadows from props + building kit | −1.4 | −1.3 | −0.9 | −0.4 | −1.5 |
| no shadows from trees | −0.4 | −0.6 | −0.3 | −0.3 | −0.7 |
| no shadows from ground | 0.0 | 0.0 | 0.0 | −0.2 | 0.0 |
| **far layer hidden** | −3.2 | −0.3 | −5.4 | −7.0 | −4.7 |
| camera far 1500 → 600 m | −2.6 | −0.2 | −2.9 | −4.2 | −2.9 |
| buildings + kit hidden | −4.1 | −3.9 | −1.6 | −0.9 | −2.0 |
| near ground hidden | −2.2 | −2.1 | −1.8 | −1.5 | −2.9 |
| trees hidden | −1.0 | −0.9 | −0.9 | −0.5 | −1.4 |
| grass hidden | −0.5 | −1.2 | 0.0 | −0.2 | −0.7 |
| props hidden | −0.4 | −0.2 | −0.1 | −0.3 | −0.7 |
| RER B hidden | −0.1 | −0.1 | +0.2 | −0.3 | −1.1 |
| ground + building + far shaders → flat vertex colour | −1.4 | −1.3 | −1.5 | −1.5 | −1.7 |
| FSR 67 % | −1.8 | −1.4 | −1.2 | −1.5 | −1.9 |
| FSR 50 % (power-saver run) | −3.3 | −3.5 | −2.4 | −2.6 | −4.1 |
| streaming off (full detail everywhere) | +9.4 | +1.0 | +10.3 | +12.6 | +10.2 |

The far layer split by part (another run, same views):

| Hidden part | Forecourt | Hillside | Overview |
|---|---:|---:|---:|
| far ground | −0.9 | −1.8 | −2.3 |
| far buildings | −2.9 | −1.8 | −1.9 |
| far tree crowns | −1.0 | −2.2 | −1.3 |
| far shadows off | 0.0 | −0.1 | +0.1 |
| far shaders → flat | −0.3 | −0.4 | −0.8 |

What this shows:
- Streaming does its job: without it, frames are 10–13 ms slower.
- The far layer costs 3–8 ms. Shaders and shadows are not the cause. The cost is spread over ~120 cells × 3–4 draws and many tiny triangles (crowns of 20 triangles a few pixels wide).
- Lowering the resolution is not the lever on an iGPU. Your own `settings.cfg` (Low + 50 % 3D resolution) gains only 2.4–4 ms.

Night mode (Low, no bots, so no headlights): +0.5 to +3 ms GPU at street level, and +4 ms at the RER B station.

### 3.2 Actions (GPU)

**G1. Make Low actually lighter on shadows.**
- **Problem:** [game.gd:535-543](godot/scripts/game.gd#L535-L543) only switches off SSAO, SSIL, glow and MSAA. The Sun keeps 4 splits, a 4096 atlas and 250 m. The settings page even describes High as "shadows, ambient occlusion, glow" ([settings_menu.gd:118](godot/scripts/settings_menu.gd#L118)).
- **Fix:** on Low, use `directional_shadow_mode = PARALLEL_2_SPLITS`, `RenderingServer.directional_shadow_atlas_set_size(2048, true)` and ~150 m.
- **Gain:** about 1.5–3 ms (est., from the rows above, which don't add up exactly).
- **Tradeoff:** blurrier shadows that pop at a shorter distance, on Low only.
- **Effort:** about 10 lines.

**G2. Fewer shadow casters (both presets).**
- **Problem:** every kit, prop and Label3D node casts shadows ([prop_placer.gd:162-167](godot/scripts/builder/prop_placer.gd#L162-L167), [building_builder.gd:455-460](godot/scripts/builder/building_builder.gd#L455-L460)).
- **Fix:** a per-model `"shadow"` flag in the kit and prop catalogues: off for roof railings, slats, fins, loggia railings, fences, bollards, sign poles, rail sleepers and the 450 labels.
- **Gain:** up to the measured 0.4–1.5 ms.
- **Tradeoff:** thin things lose their shadows. If some matter up close, a shadow-only copy with `visibility_range_end` ≈ 50 m keeps them there.
- **Effort:** small, plus a rebuild.

**G3. The far layer (3–8 ms; 1–3 ms on the RTX).**
- **a. Shorter view distance on Low.**
  - **Fix:** camera far ~600–800 m, with depth fog in the sky's horizon colour so the cut is not visible.
  - **Measured:** −2.6 to −4.2 ms.
  - **Tradeoff:** the horizon fades out, and the plane sees less of the map.
  - **Effort:** small (game.gd/night.gd).
- **b. Far tree crowns end at ~500 m.**
  - **Fix:** set `visibility_range_end` on `Far/*/Trees`. Those crowns are a few pixels wide.
  - **Est.:** −1 to −2 ms.
  - **Tradeoff:** less tree mass on the far horizon.
  - **Effort:** tiny (far_builder).
- **c. Coarser super-cells beyond ~500 m.**
  - **Fix:** merge 4×4 far cells into one mesh per material. That is ~4× fewer far draws, and the far ground grid can be coarser out there.
  - **Effort:** medium (far_builder + streamer).
- **d. Compact the far building vertex buffers.**
  - **Problem:** they keep all 1.74 M source vertices to draw ~90 k triangles (est. 181 MB → ~10 MB).
  - **Gain:** VRAM rather than fps.
  - **Effort:** small.

**G4. A LOD for the building kit.**
- **Problem:**
  - A balcony is 764 triangles and is placed 7,482 times.
  - A roof railing is 432 triangles and is placed 8,864 times.
  - Both are drawn out to 260 m and cast shadows.
  - The builders drop any import LODs ([building_builder.gd:473-478](godot/scripts/builder/building_builder.gd#L473-L478)).
- **Fix:** a lod1 model in the Blender kit (railing ≈ 24 triangles, balcony ≈ 40), emitted as a second MultiMesh from 60 to 260 m, as the trees already do.
- **Est.:** about 1 M fewer triangles in town, counted again in the prepass and in each shadow split.
- **Tradeoff:** Blender work, and twice as many kit MultiMesh nodes.
- **Effort:** medium.

**G5. Buildings.**
- **Problem:** 2,483 separate MeshInstance3D nodes. Hiding buildings + kit saves 0.9–4.1 ms.
- **Options:**
  - Merge buildings per 48–96 m chunk: far fewer main and shadow draws. **Tradeoff:** coarser culling, and the picker would read metadata from the collision shapes, which already carry it.
  - Occlusion culling: an `ArrayOccluder3D` per cell from the tier prisms the builder already makes for collision, then `use_occlusion_culling`. **Tradeoff:** ~0.5 ms CPU; it helps only at street level, and shadow passes are never occlusion-culled.
- **Effort:** medium.

**G6. Vehicles on screen (not measured: tool runs with bots crash).**
- **Problem:**
  - A 12 m bus is 79 surfaces, an articulated bus 122.
  - They have no visibility range and everything casts shadows.
  - About 23 bot buses are on the road.
- **Fix:** do what the MI 79 train already does: a merged far shell plus visibility ranges ([train.gd:473-482](godot/scripts/train.gd#L473-L482)), and share materials between vehicles.
- **Night:** each bot has a 60 m spot light. On Low, use shorter ranges and fades, or emissive lamps only.

**G7. Grass (≤ 1.2 ms, low priority).**
- **Problem:** `grass_tone` (an fbm) runs for every vertex although it is the same for the whole tuft ([toy_grass.gdshader:26](godot/shaders/toy_grass.gdshader#L26)), and the blade tips are zero-width quads.
- **Fix:** compute the tint per instance, make each tip one triangle, and halve the density on Low.

**G8. Procedural shaders (≤ 1.7 ms on Low).**
- **Problem:** on High, the SSAO/SSIL prepass runs the ground's bump code and the building's roughness logic once more.
- **Fix:** skip the detail branches where `detail()` is 0 or the building's `far` term is 1.
- **Priority:** low.

---

## 4. The High preset and how the preset is chosen

Measured (frame-time change in ms when the feature is off):

| | RTX 4050 (base 7.9–9.3 ms) | Iris Xe on High (base 42–44 ms) |
|---|---:|---:|
| 2× MSAA | −1.5 to −2.0 | **−13.8 to −16.9** |
| SSIL | −0.9 to −1.2 | −3.9 to −4.5 |
| glow | −0.5 to −0.6 | −1.6 to −1.7 |
| SSAO | −0.3 to −0.4 | −1.5 to −1.6 |
| shadows | −0.6 to −1.5 | (not run) |
| far layer | −1.0 to −3.3 | (not run) |

**H1. Choose "auto" by performance, not by adapter type.**
- **Problem:** [settings.gd:224](godot/scripts/settings.gd#L224) checks only `DEVICE_TYPE_INTEGRATED_GPU`. A laptop MX450 or an old GTX 1050 reports as discrete and gets High, where MSAA + SSIL can halve the frame rate.
- **Options:**
  - Time ~3 s at a fixed view on first start.
  - Or adapt at runtime: after 10 s above ~20 ms per frame on High, offer or switch to Low.
- **Effort:** small to medium.

**H2. A Medium preset.**
- **Fix:** shadows + SSAO + FXAA, without SSIL and MSAA. MSAA and SSIL are the two most expensive High features everywhere.
- **Tradeoff:** jaggier edges (the flat toy colours show aliasing) and a little less bounce light.

**H3. Automatic 3D scale on High too.**
- **Problem:** the automatic cap at 1920 px applies only on Low ([settings.gd:230-235](godot/scripts/settings.gd#L230-L235)). A 4K Windows laptop with a discrete GPU renders High at native 4K, about 4× the pixels measured here.
- **Fix:** cap "auto" at ~2560 px wide on High too.
- **Tradeoff:** softer image on 4K screens, unless the player sets 100 %.

---

## 5. Windows

**W1. Power plans (most important).**
- **Problem:** Windows laptops on battery or in "Best power efficiency" throttle the CPU like GNOME power-saver. Measured here, that means 6 fps even with an RTX 4050 (section 2). Cheap 15 W quad-core laptops are in that situation even when plugged in.
- **Fix:** C1–C8. Also add the physics tick time to the F3 overlay so players can report "CPU" against "GPU".

**W2. Rendering driver.**
- Godot 4.7.2's default on Windows is **Vulkan**: the engine's own docs give `rendering/rendering_device/driver.windows` a default of `"vulkan"`.
- The uncommitted change in `godot/project.godot` that removes `rendering_device/driver.windows="vulkan"` therefore changes nothing; the editor drops settings equal to their default.
- The fallbacks are D3D12, then **OpenGL 3**, i.e. the Compatibility renderer: a different look, no SSAO/SSIL. It has never been tried with these shaders.
- **Suggestions:**
  - Try it once: `--rendering-method gl_compatibility --rendering-driver opengl3`.
  - Then either accept it as a last resort or set `fallback_to_opengl3=false`.
  - On Intel iGPUs with old Windows Vulkan drivers, a launch option `--rendering-driver d3d12` can be faster or more stable. **Tradeoff:** a slower first-run shader compile. Test before recommending it.

**W3. Shader baker.**
- **Current state:** off in both presets ([export_presets.cfg:36](godot/export_presets.cfg#L36), [export_presets.cfg:177](godot/export_presets.cfg#L177)).
- **Measured on Linux/Mesa:** a cold cache costs +1.4 s at load and one 45 ms frame. Windows drivers can be slower.
- **What baking gives:** a shorter first start and fewer first-sight hitches.
- **Tradeoff:** a longer export and a bigger pack.
- **To check:** whether the Linux CI can bake for the Windows Vulkan target. Some drivers (D3D12, Metal) have host restrictions.

**W4. Hybrid graphics (Optimus).**
- Godot picks the discrete GPU itself, but Windows' per-app graphics settings or the driver panel can force the iGPU.
- Auto-Low covers that case.
- Showing the adapter name in F3 or on the settings page would make reports easier.

**W5. First start of the packed builds.**
- **Problem:** the 160+ MB unpacked pack and the large files read at load are scanned by Defender. A main thread blocked for more than 5 s shows "(Not Responding)".
- **Fix:**
  - Load `main.tscn` with `ResourceLoader.load_threaded_request` behind a progress bar.
  - Run the update check in parallel with the unpack.
  - Ship the 2 m height grid instead of `heightmap.f32`: 57 MB read, then decimated in GDScript ([ground_heights.gd:16-28](godot/scripts/ground_heights.gd#L16-L28)). That is ~53 MB less to download, unpack and scan.

**W6. Network-interface polling.**
- **Problem:** `IP.get_local_interfaces()` runs twice per second while hosting ([lan_discovery.gd:111](godot/scripts/lan_discovery.gd#L111)). On Windows with VPN or Hyper-V adapters, this can take several ms.
- **Fix:** cache it for 10–30 s.
- (Code reading only.)

---

## 6. Other findings

### 6.1 Crash in tool runs with bots

**How to reproduce:** `PLATEAU_BUSES=1 godot --headless --path godot --script res://tools/perf.gd`. It crashes with SIGSEGV after ~13 viewpoints (~10 s).

**Backtrace:** `put` ([bus_bot.gd:563](godot/scripts/bus_bot.gd#L563), `car.set_indicator(0)`) ← `_depart` ([traffic.gd:232](godot/scripts/traffic.gd#L232)).

**When it happens:**
- It reproduces in 14 of 14 runs: windowed and headless, with or without trains, with the Dummy audio driver, with `perf.gd` and with my probe.
- It does not happen in the real game (45–100 s runs, windowed and headless), nor in `test_bus_bots` (28 ok, `--fixed-fps`).

**What it looks like:**
- The windowed run jumps to a garbage address, which suggests a call on a freed object.
- The headless run shows a short repeating native recursion.

It is worth a look with a debug build of the engine, in case the real game can reach the same state.

### 6.2 Smaller items

**Loading, measured:** 6.3 s to the first frame from the editor-format scene (a 27.5 MB text `.tscn`; exports convert it to binary), plus 1.4 s with a cold shader cache.

**Spawn and first-use hitches (est., code reading):**
- `mesh.surface_get_arrays()` at every bus or realistic-car spawn reads mesh data back from the GPU ([car.gd:861](godot/scripts/car.gd#L861)).
- The horn and the one-shot sounds are synthesized on the main thread ([vehicle_audio.gd:589-608](godot/scripts/vehicle_audio.gd#L589-L608)). Their cache is cleared when the last vehicle leaves.
- Each train car instances the whole `mi79.glb` ([train.gd:456-466](godot/scripts/train.gd#L456-L466)).
- The first switch to night reads back the 71 lamp meshes ([night.gd:113-180](godot/scripts/night.gd#L113-L180)).
- All ~100 bots are spawned in one frame ([traffic.gd:253-256](godot/scripts/traffic.gd#L253-L256)), and so is every vehicle when a LAN client joins ([net.gd:358](godot/scripts/net.gd#L358)).
- **Fix:** cache per model, synthesize on a worker thread at boot, and spread spawns over several frames.

**VRAM, measured:** 847 MB, of which 556 MB are mesh buffers. The far building vertex compaction (G3d) and packed building vertex formats (CUSTOM channels as RGBA8/half floats, indexed: est. 182 → ~80 MB) would leave room for 2 GB GPUs and for iGPUs that share system RAM.

**LAN bandwidth (est.):**
- A vehicle state is about 185 B: two `Transform3D`, plus an identity trailer transform for non-articulated vehicles. That is roughly 1.8 Mbit/s per client with the full traffic.
- **Fix:** compact quantized states, `host.compress(ENetConnection.COMPRESS_RANGE_CODER)`, and a distance LOD for remote vehicles on clients. Clients currently pose and update every remote vehicle every tick ([net.gd:818-822](godot/scripts/net.gd#L818-L822)).

**Dedicated server:** the headless costs of section 2 apply to the VPS, whose vCPU is probably slower than this laptop. Players spread over the map stop bots from gliding (11.4 ms per tick here). C1–C5 matter for the server too.

**Already in place, so not proposed again:**
- chunk streaming
- bots glide beyond 200 m and tick every 3rd frame
- engines silent beyond 160 m
- beam shadows only on the player's own vehicle
- tree LODs
- engine sounds synthesized on a worker thread
- tree and prop collision added outside the physics space
- split breakable compounds
- throttled HUD updates

---

## 7. Suggested order

1. **C1, C3, C6, C7, C10, C8.** Small changes, no visible tradeoff. They target the power-saver collapse and help the VPS server. Re-measure with `probe_traffic.gd` in both power profiles. **Done 2026-10-17, see 2.3.**
2. **C5, then C4.** The remaining per-tick scans.
3. **G1, G2, G3a, G3b.** Low preset and catalogue flags: about 5–8 ms on the iGPU in the worst views (est., not measured together).
4. **H1 + H2** (preset choice), then **C2** (traffic density) if weak CPUs still struggle.
5. Bigger jobs, as needed: G4 (kit LOD), G3c (far super-cells), G5 (merging or occlusion culling), G6 (vehicle far shells), loading and VRAM.

## 8. Re-measuring

```sh
cd godot
# CPU per tick, steady state = second minute (real s per sim minute / 3600 = ms per tick)
PLATEAU_TRAINS=1 godot --headless --fixed-fps 60 --path . --script res://tools/probe_traffic.gd -- 2
powerprofilesctl set power-saver   # then re-run; set it back to performance afterwards

# GPU per viewpoint on the iGPU (X11, see project notes), with feature toggles
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/intel_icd.json godot --display-driver x11 --resolution 1920x1080 \
    --path . --script res://tools/_tmp_perfprobe.gd -- --only=telecom_entrance,lozere_hillside,overview \
    --variants=base,no_shadow,no_far,shadow_atlas_2k,base
# hitches along a bus route: --drive=<route id>,<m/s>,<max s>[,<start m>]
#   e.g. --drive=4606:2393305,25,130 (without PLATEAU_BUSES: tool runs with bots crash, 6.1)

# the real game (uses your settings.cfg: vsync and 3D scale apply)
godot --display-driver x11 --print-fps --path . -- --solo
```
