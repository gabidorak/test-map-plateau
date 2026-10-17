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
  parts, own untextured materials, dense parts decimated (~115k triangles), number plates blank (the bundled texture
  has a real-looking German registration), maker's badges plain (no roundels, M stripes or tyre lettering).
- `audi_r8.glb`: Audi R8 V10 (2016), a ready-made 3D model supplied by the project owner (`audi r8.zip`, its OBJ; the
  files stay in `ref/AUDI_R8_2016/`, not published; the archive names no author or licence: to be confirmed),
  converted by `blender/vehicles/import_car.py`: split into the game's parts, own untextured materials, dense parts
  decimated (~119k triangles), the cabin's instrument cluster added, number plate blank, the four rings and badges
  dropped (the archive's R8 logo and tyre-wall textures are not used).
- `audi_rs6.glb`: Audi RS6 Avant "Starwars Hycade" (2016; a wide-body kit), a ready-made 3D model supplied by the
  project owner (`audi RS6.zip`, its OBJ; the files stay in `ref/audi_rs6/`, not published; the archive names no
  author or licence: to be confirmed), converted by `blender/vehicles/import_car.py`: split into the game's parts, own
  untextured materials and paint, honeycomb grilles turned into sheets, dense parts decimated (~109k triangles), the
  model's bare cabin fitted out with `build_car.py`'s, plates blank, the four rings dropped (the archive's "Audi RS6"
  plate and tyre-wall textures are not used).
- `mercedes_1928/`: a 1928 Mercedes tourer (Mercedes-Benz SSK type, hood up), a ready-made textured 3D model supplied
  by the project owner (`mercedes 1928.rar`, its OBJ and PBR textures; the files stay in `ref/mercedes_1928/`, not
  published; the archive names no author or licence: to be confirmed), converted by
  `blender/vehicles/import_textured.py`: split into the game's parts, its own textures downscaled (base colour,
  normal, occlusion-roughness-metallic), decimated (~121k triangles), number plate blank, the maker's three-pointed
  stars dropped (bonnet mascot, rear lamp badges; their baked shadow painted out of the textures).
- `volvo_fh16.glb`, `volvo_fh16_trailer.glb`: Volvo FH16 750 tractor unit (Globetrotter cab), alone and with its
  three-axle curtain-sider semi-trailer, a ready-made 3D model supplied by the project owner (`VOLVO FH16.zip`, its
  FBX; the files stay in `ref/volvo_fh16/`, not published; the archive's preview renders carry a 3dsky.org mark,
  original author and licence to be confirmed), converted by `blender/vehicles/import_truck.py`: split into the game's
  parts, own untextured materials, dense parts decimated (~158k triangles, ~233k with the trailer), number plates blank
  (the bundled texture is a real-looking German registration), the sun visor's "GLOBETROTTER" and the curtains' print
  left out (textures), the maker's name and iron mark dropped (the plain "FH" and "750" badges stay).
