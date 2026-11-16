"""Employment and unemployment by region (stage S6.2).

    python tools/uk/regions.py         extract from the cached download

Reads the Annual Population Survey's people aged 16 and over in employment and unemployed,
by region, January to December 2024 (ONS, through Nomis; Open Government Licence v3.0),
which `python tools/uk/pipeline.py fetch aps_regions` downloads, and writes
models/uk/data/labour_regions.csv: per region of the model's region dimension, people in
employment and unemployed, and the unemployment rate.
"""

from __future__ import annotations

import csv
import io
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache" / "uk"
OUT = ROOT / "models" / "uk" / "data" / "labour_regions.csv"
REGIONS = {"North East": "north_east", "North West": "north_west", "Yorkshire and The Humber": "yorkshire",
           "East Midlands": "east_midlands", "West Midlands": "west_midlands", "East": "east", "London": "london",
           "South East": "south_east", "South West": "south_west", "Wales": "wales", "Scotland": "scotland",
           "Northern Ireland": "northern_ireland"}


def main() -> int:
    rows = list(csv.DictReader(io.StringIO((CACHE / "aps_regions.csv").read_text(encoding="utf-8-sig"))))
    table = {}
    for r in rows:
        table.setdefault(REGIONS[r["GEOGRAPHY_NAME"]], {})[r["C_ECOPUK11_NAME"]] = int(r["OBS_VALUE"])
    lines = ["region,employed,unemployed,unemployment_rate"]
    for region in REGIONS.values():
        e, u = table[region]["Employed"], table[region]["Unemployed"]
        lines.append(f"{region},{e},{u},{u / (e + u)!r}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    total_e = sum(t["Employed"] for t in table.values())
    total_u = sum(t["Unemployed"] for t in table.values())
    print(f"wrote {OUT.relative_to(ROOT)}: 12 regions, {total_e:,} employed, unemployment {total_u / (total_e + total_u):.2%}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
