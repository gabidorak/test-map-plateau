# Car models

- `ambulance.glb` … `van.glb` + `Textures/colormap.png`: Car Kit 3.1 by Kenney (www.kenney.nl), CC0 — see `LICENSE.txt`.
  Source: https://kenney.nl/assets/car-kit
- `kaykit_hatchback.glb`: "Car Hatchback" by Kay Lousberg (KayKit), CC0.
  Source: https://poly.pizza/m/BG0KAhmGDt
- `bus_idfm.glb`: Île-de-France Mobilités city bus (Iveco Urbanway 12 m CNG), built from code by
  `blender/vehicles/build_bus.py`; livery after the photos in `ref/`.
- `bus_idfm_artic.glb`: the same as an 18 m articulated bus (Iveco Urbanway 18 m CNG), `build_bus.py --model=artic`.
- `fire_truck.glb`: 6x6 airport fire truck (crash tender on a heavy cab-over chassis), built from code by
  `blender/vehicles/build_fire_truck.py` after the photo `ref/fire_truck.png`.
- `compact_hatchback.glb`, `family_suv.glb`: realistic five-door hatchback and compact SUV with fitted-out cabins,
  built from code by `blender/vehicles/build_car.py` (proportions of a Renault Clio V and a Peugeot 3008 II, no badges).
- `police_hatchback.glb`: the compact hatchback in the Police nationale livery (2021 on), light bar and grille flashers,
  `build_car.py`; its lettering is drawn with Noto Sans (SIL Open Font License) from the system fonts.
- `renault_zoe.glb`: Renault Zoe (2013), a ready-made 3D model supplied by the project owner (the FBX/MAX files stay
  in `ref/RENAULT_ZOE_2013/`, not published; original author and licence to be confirmed), converted by
  `blender/vehicles/import_car.py`: split into the game's parts, own materials, dense parts decimated, number plates
  left blank (the bundled plate texture is a watermarked stock picture).
- `bmw_m4.glb`: BMW M4 coupé (F82, 2015), a ready-made 3D model supplied by the project owner (`BMW M4.zip`, its LOW
  FBX; the files stay in `ref/BMW_M4_2015/`, not published; the archive's preview renders carry a 3dsky.org mark,
  original author and licence to be confirmed), converted by `blender/vehicles/import_car.py`: split into the game's
  parts, own materials, dense parts decimated (~119k triangles), number plates blank (the bundled texture has a
  real-looking German registration); the maker's marks are the model's own: the BMW roundels (bonnet, boot lid, wheel
  caps, steering wheel), the M4 badges' M stripes, and its textures cropped and downscaled for the roundels, the
  tyres' sidewall lettering and the cabin's dials, screens and switch prints (`bmw_m4_*.jpg/png`, extracted by Godot
  from the glb).
- `audi_r8.glb`: Audi R8 V10 (2016), a ready-made 3D model supplied by the project owner (`audi r8.zip`, its OBJ; the
  files stay in `ref/AUDI_R8_2016/`, not published; the archive names no author or licence: to be confirmed),
  converted by `blender/vehicles/import_car.py`: split into the game's parts, own materials, dense parts decimated
  (~132k triangles), the cabin's instrument cluster added, number plate blank; the model's marks kept (the four rings
  front, rear and on the centre caps, the R8 and V10 badges, chrome) and its tyre-wall texture on the tyres
  (`audi_r8_tyre_print.jpg`, extracted by Godot from the glb; the R8 logo texture of its plate is not used).
- `audi_rs6.glb`: Audi RS6 Avant "Starwars Hycade" (2016; a wide-body kit), a ready-made 3D model supplied by the
  project owner (`audi RS6.zip`, its OBJ; the files stay in `ref/audi_rs6/`, not published; the archive names no
  author or licence: to be confirmed), converted by `blender/vehicles/import_car.py`: split into the game's parts, own
  materials and paint, honeycomb grilles turned into sheets, dense parts decimated (~112k triangles), the model's
  bare cabin fitted out with `build_car.py`'s; its maker's marks kept: the four rings (chrome) front and back, and with
  the archive's own textures the "Audi RS6" show plates (`audi_rs6_plate_show.jpg`) and the tyres' Michelin Pilot
  Sport 4 sidewall lettering (a normal map, `audi_rs6_tyre_michelin.png`; both extracted from the glb by Godot).
- `mercedes_1928/`: a 1928 Mercedes tourer (Mercedes-Benz SSK type, hood up), a ready-made textured 3D model supplied
  by the project owner (`mercedes 1928.rar`, its OBJ and PBR textures; the files stay in `ref/mercedes_1928/`, not
  published; the archive names no author or licence: to be confirmed), converted by
  `blender/vehicles/import_textured.py`: split into the game's parts, its own textures downscaled (base colour,
  normal, occlusion-roughness-metallic), decimated (~123k triangles; the maker's three-pointed stars, the bonnet
  mascot and the rear lamp badges, kept whole), number plate blank.
- `volvo_fh16/`: Volvo FH16 750 tractor unit (Globetrotter cab), alone (`volvo_fh16.gltf`) and with its three-axle
  curtain-sider semi-trailer (`volvo_fh16_trailer.gltf`), a ready-made 3D model supplied by the project owner
  (`VOLVO FH16.zip`, its FBX and maps; the files stay in `ref/volvo_fh16/`, not published; the archive's preview
  renders carry a 3dsky.org mark, original author and licence to be confirmed), converted by
  `blender/vehicles/import_truck.py`: split into the game's parts, own materials, dense parts decimated (~168k
  triangles, ~250k with the trailer), number plates blank (the bundled texture is a real-looking German registration).
  The maker's marks are kept: the iron mark and VOLVO lettering (geometry), and from the archive's maps the sun visor's
  "GLOBETROTTER" (`visor_print.png`), the tyres' Michelin sidewall lettering (`tyre_print*.*`, from its height map)
  and the curtains' hexagon print (`curtain_print.jpg`).
- `gaz_tiger.glb` (+ `gaz_tiger_tiger_logo.png`): GAZ Tiger-M armoured car (GAZ-233115, the "SPM-2" body) with a PKM
  machine gun on its roof hatch, a ready-made 3D model supplied by the project owner (`Gaz Tiger M 23115.rar`, a zip of
  3ds Max files and an FBX 6.1 by "Sergio" per its file list; the files stay in `ref/gaz_tiger/`, not published;
  author and licence to be confirmed), read through Godot's FBX importer (`godot/tools/fbx_to_glb.gd`) and converted
  by `blender/vehicles/import_car.py`: split into the game's parts (the gun's ring and the gun turn), own untextured
  materials (matt protective green), the cabin's single-skinned hull lined on the inside, dense parts decimated (~157k
  triangles), the grille's tiger-head emblem textured from the archive's `logo_tigr.jpg`.
