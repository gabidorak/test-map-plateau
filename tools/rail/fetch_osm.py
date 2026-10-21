"""Fetches the OpenStreetMap data of the RER B (Ligne de Sceaux) across the map into tools/rail/osm_rail.json.

python tools/rail/fetch_osm.py [--out tools/rail/osm_rail.json]
python tools/rail/fetch_osm.py --massy [--out tools/rail/osm_rail_massy.json]
python tools/rail/fetch_osm.py --west [--out tools/rail/osm_rail_west.json]

The committed osm_rail.json is what build_rail.py reads, so the railway rebuilds the same way without the network;
rerun this to take OSM edits in (then build_rail.py and patch_world.py). Overpass query (BOX: the line's corridor, the
map's data box x -250..1810 widened to x -600..2150 so the trains' routes start and end beyond it, y -1000..-700):
- the tracks (railway=rail named "Ligne de Sceaux"), the platforms, every railway node (signals, stop positions,
  milestones, the station, its entrances, switches);
- within 40 m of the tracks: highways (roads, paths, steps, the tunnels and bridges crossing the line), buildings,
  barriers (fences, walls, retaining walls), man_made=bridge.
--massy: the line on east to Massy-Palaiseau (the map's corridors, 2026-10-18), into osm_rail_massy.json, which
build_rail.py reads under osm_rail.json (that one's elements win, so the first stretch stays as it was): BOX_MASSY,
the tracks and every other railway track there (the decorative tracks: yards, the TGV line, the RER C), the platforms
(ways and multipolygons) and railway nodes within 80 m of the tracks, and the same highways, buildings and barriers.
--west: the line on south-west through Le Guichet out of the map's west box (2026-10-21), into osm_rail_west.json,
read under the other two likewise: BOX_WEST, the tracks, their platforms (ways and multipolygons) and railway nodes
within 80 m, and the same highways, buildings and barriers.
Overpass answers 406 without a User-Agent, hence USER_AGENT. Data © OpenStreetMap contributors (ODbL).
"""
import argparse
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from l93 import inv  # noqa: E402

OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.private.coffee/api/interpreter",
            "https://overpass.kumi.systems/api/interpreter"]      # tried in turn (busy servers answer 502/504)
USER_AGENT = "plateau-map/1.0 (tools/rail/fetch_osm.py)"
BOX = (-600.0, -1000.0, 2150.0, -700.0)     # map metres: x0, y0, x1, y1
NEAR = 40                                   # m around the tracks for highways, buildings and barriers
QUERY = """[out:json][timeout:180];
way["railway"="rail"]["name"="Ligne de Sceaux"]({bbox})->.tracks;
(
  .tracks;
  way["railway"="platform"]({bbox});
  node["railway"]({bbox});
  way(around.tracks:{near})["highway"];
  way(around.tracks:{near})["building"];
  way(around.tracks:{near})["barrier"];
  way(around.tracks:{near})["man_made"="bridge"];
);
out body geom;
"""
BOX_MASSY = (1500.0, -1150.0, 4900.0, 1800.0)
QUERY_MASSY = """[out:json][timeout:240];
way["railway"="rail"]["name"="Ligne de Sceaux"]({bbox})->.tracks;
(
  .tracks;
  way["railway"~"^(rail|light_rail)$"]({bbox});
  way["railway"="platform"](around.tracks:80);
  relation["railway"="platform"](around.tracks:80);
  way["public_transport"="platform"](around.tracks:80);
  relation["public_transport"="platform"](around.tracks:80);
  node["railway"](around.tracks:80);
  node["public_transport"](around.tracks:80);
  way(around.tracks:{near})["highway"];
  way(around.tracks:{near})["building"];
  way(around.tracks:{near})["barrier"];
  way(around.tracks:{near})["man_made"="bridge"];
);
out body geom;
"""
BOX_WEST = (-1150.0, -1700.0, -150.0, -650.0)
QUERY_WEST = """[out:json][timeout:180];
way["railway"="rail"]["name"="Ligne de Sceaux"]({bbox})->.tracks;
(
  .tracks;
  way["railway"="platform"](around.tracks:80);
  relation["railway"="platform"](around.tracks:80);
  way["public_transport"="platform"](around.tracks:80);
  relation["public_transport"="platform"](around.tracks:80);
  node["railway"](around.tracks:80);
  node["public_transport"](around.tracks:80);
  way(around.tracks:{near})["highway"];
  way(around.tracks:{near})["building"];
  way(around.tracks:{near})["barrier"];
  way(around.tracks:{near})["man_made"="bridge"];
);
out body geom;
"""


def bbox(box=BOX) -> str:
    """Overpass bbox (south, west, north, east) around `box`."""
    lats, lons = [], []
    for x in (box[0], box[2]):
        for y in (box[1], box[3]):
            lat, lon = inv(x, y)
            lats.append(lat)
            lons.append(lon)
    return "%.6f,%.6f,%.6f,%.6f" % (min(lats), min(lons), max(lats), max(lons))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--massy", action="store_true", help="the extension to Massy-Palaiseau (osm_rail_massy.json)")
    ap.add_argument("--west", action="store_true", help="the line on through Le Guichet (osm_rail_west.json)")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    name = "osm_rail_massy.json" if a.massy else "osm_rail_west.json" if a.west else "osm_rail.json"
    a.out = a.out or str(Path(__file__).resolve().parent / name)
    query = (QUERY_MASSY.format(bbox=bbox(BOX_MASSY), near=NEAR) if a.massy else
             QUERY_WEST.format(bbox=bbox(BOX_WEST), near=NEAR) if a.west else QUERY.format(bbox=bbox(), near=NEAR))
    data = None
    for url in OVERPASS:
        req = urllib.request.Request(url, data=urllib.parse.urlencode({"data": query}).encode(),
                                     headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=240) as r:
                data = json.load(r)
            break
        except OSError as e:
            print("%s: %s" % (url, e))
    if data is None:
        sys.exit("no Overpass server answered")
    data["elements"].sort(key=lambda e: (e["type"], e["id"]))
    data.pop("generator", None)
    data["query"] = query
    Path(a.out).write_text(json.dumps(data, indent=0, ensure_ascii=False) + "\n", encoding="utf-8")
    kinds = {}
    for e in data["elements"]:
        kinds[e["type"]] = kinds.get(e["type"], 0) + 1
    print("osm_rail.json: %s, OSM timestamp %s" % (kinds, data.get("osm3s", {}).get("timestamp_osm_base", "?")))


main()
