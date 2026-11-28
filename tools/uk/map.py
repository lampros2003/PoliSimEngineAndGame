"""The United Kingdom's regions as a small map for the game (stage S18.4).

    python tools/uk/map.py            make models/uk/map/regions.geojson from the cached download
    python tools/uk/map.py --fetch    download the boundaries first

Reads the Office for National Statistics' International Territorial Level 1 boundaries of
January 2025 (the nine English regions, Scotland, Wales and Northern Ireland), ultra
generalised and clipped to the coastline, on the British National Grid (EPSG:27700); Open
Government Licence v3.0. The open tool mapshaper (https://github.com/mbloch/mapshaper,
MPL-2.0; run through `npx`, so Node.js is needed) then

- drops islands under 120 square kilometres, which are specks at the size the game draws,
- thins the outlines to what shows at that size (weighted Visvalingam, which smooths a
  coast where Douglas-Peucker leaves it spiked; 3 km), keeping the regions' shared edges
  shared,
- rounds to 100 metres and repairs what rounding crossed,
- names each region by its ITL code (`code`) and name (`name`), and
- writes, beside the regions, the lines between and around them, each with the codes either
  side (`a`, and `b`: empty on the coast), so the game can draw a coast, and a border only
  between two different places.

The result is GeoJSON with one feature a line, so a change to it can be read.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache" / "uk"
SOURCE = CACHE / "itl1_boundaries.geojson"
OUT = ROOT / "models" / "uk" / "map" / "regions.geojson"

TITLE = "International Territorial Level 1 (January 2025) Boundaries UK BUC"
PAGE = "https://geoportal.statistics.gov.uk/datasets/67ad9f4414934171a08051d408cee70d"
URL = ("https://services1.arcgis.com/ESMARspQHYMw9BZ9/arcgis/rest/services/ITL1_JAN_2025_UK_BUC/FeatureServer/0/query"
       "?where=1%3D1&outFields=*&outSR=27700&f=geojson")
LICENCE = "Open Government Licence v3.0"
ATTRIBUTION = ("Source: Office for National Statistics licensed under the Open Government Licence v.3.0. "
               "Contains OS data © Crown copyright and database right 2025.")
MAPSHAPER = "mapshaper@0.6.121"
USER_AGENT = "polisim-data-pipeline"


def fetch() -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=600) as response:
        data = response.read()
    SOURCE.write_bytes(data)
    meta = {"retrieved": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    SOURCE.with_suffix(".meta.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
    print(f"fetched the boundaries: {len(data):,} bytes")


def make() -> int:
    if not SOURCE.exists():
        raise SystemExit(f"no {SOURCE.relative_to(ROOT)}: run with --fetch first")
    npx = shutil.which("npx")
    if npx is None:
        raise SystemExit("npx (Node.js) is needed to run mapshaper")
    meta_path = SOURCE.with_suffix(".meta.json")
    meta = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else {}
    with tempfile.TemporaryDirectory() as folder:
        made = Path(folder) / "regions.json"
        subprocess.run([
            npx, "--yes", MAPSHAPER, str(SOURCE),
            "-filter-islands", "min-area=120000000",
            "-simplify", "weighted", "interval=3000", "keep-shapes", "planar",
            "-snap", "precision=100",
            "-clean",
            "-each", "code=ITL125CD, name=ITL125NM",
            "-filter-fields", "code,name",
            "-lines", "+", "name=lines", "each=a = A.code, b = B ? B.code : ''",
            "-filter-fields", "a,b", "target=lines",
            "-o", str(made), "format=geojson", "combine-layers", "precision=1", "target=*",
        ], check=True)
        features = json.loads(made.read_text(encoding="utf-8"))["features"]
    regions = [f for f in features if f["geometry"]["type"] in ("Polygon", "MultiPolygon")]
    lines = [f for f in features if f["geometry"]["type"] in ("LineString", "MultiLineString")]
    if len(regions) != 12:
        raise SystemExit(f"{len(regions)} regions, not 12")
    head = {
        "type": "FeatureCollection",
        "title": TITLE,
        "publisher": "Office for National Statistics",
        "page": PAGE,
        "licence": LICENCE,
        "attribution": ATTRIBUTION,
        "retrieved": meta.get("retrieved", ""),
        "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "grid": "EPSG:27700 (British National Grid), metres",
        "made_by": f"tools/uk/map.py with {MAPSHAPER}",
    }
    text = json.dumps(head, ensure_ascii=False, indent=0)[:-2] + ',\n"features": [\n'
    text += ",\n".join(json.dumps(f, ensure_ascii=False, separators=(",", ":")) for f in regions + lines)
    text += "\n]}\n"
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8", newline="\n")
    points = sum(_count(f["geometry"]["coordinates"]) for f in regions)
    print(f"wrote {OUT.relative_to(ROOT)}: {len(regions)} regions of {points:,} points, {len(lines)} lines, {len(text):,} bytes")
    return 0


def _count(coordinates: list) -> int:
    if coordinates and isinstance(coordinates[0], (int, float)):
        return 1
    return sum(_count(c) for c in coordinates)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--fetch", action="store_true", help="download the boundaries first")
    arguments = parser.parse_args()
    if arguments.fetch:
        fetch()
    raise SystemExit(make())
