"""The UK's population by region, sex and single year of age (stage S3.6).

    python tools/uk/population.py          extract from the cached downloads and check

Reads two ONS workbooks that `python tools/uk/pipeline.py fetch mye24 lifetables`
downloads into .cache/uk/ (both under the Open Government Licence v3.0):

- mid-2024 population estimates: MYE2 (people by single year of age, 0 to 89 and 90 and
  over, by sex) and MYE3 (components of change, mid-2023 to mid-2024), for the 12 ITL1
  regions: the nine English regions, Wales, Scotland and Northern Ireland;
- national life tables for the UK, 2022-2024: the probability of dying within a year by
  single year of age and sex.

Writes into models/uk/data/:

- population.csv: region, sex, age, people (mid-2024);
- population_change.csv: per region, the population at mid-2023 and mid-2024, births,
  deaths, net internal and net international migration and ONS's "other" adjustment;
- life_table.csv: sex, age, qx. The open group 90 and over gets 1 - exp(-1 / e90), the
  death rate of a stationary population above 90, from the expectation of life at 90.

and POPULATION.md with the sources, file checksums and checks: the cells add up to each
region's published total and to the UK's, and each region's change adds up.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
import math
import sys
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / ".cache" / "uk"
OUT = ROOT / "models" / "uk" / "data"

# ITL1 regions in ONS order: (member name in the model, ONS code, ONS name)
REGIONS = [
    ("north_east", "E12000001", "North East"),
    ("north_west", "E12000002", "North West"),
    ("yorkshire", "E12000003", "Yorkshire and The Humber"),
    ("east_midlands", "E12000004", "East Midlands"),
    ("west_midlands", "E12000005", "West Midlands"),
    ("east", "E12000006", "East of England"),
    ("london", "E12000007", "London"),
    ("south_east", "E12000008", "South East"),
    ("south_west", "E12000009", "South West"),
    ("wales", "W92000004", "Wales"),
    ("scotland", "S92000003", "Scotland"),
    ("northern_ireland", "N92000002", "Northern Ireland"),
]
UK = "K02000001"
TOP_AGE = 90  # 90 and over


def rows_of(sheet) -> dict[str, tuple]:
    """Data rows of an ONS table sheet by area code; the header row starts with 'Code'."""
    out, header = {}, None
    for row in sheet.iter_rows(values_only=True):
        if header is None:
            if row and row[0] == "Code":
                header = row
            continue
        if row and row[0]:
            out[row[0]] = row
    return {"header": header, **out}


def write_csv(path: Path, header: list[str], rows: list[list]) -> None:
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(header)
    writer.writerows(rows)
    path.write_text(buffer.getvalue(), encoding="utf-8", newline="\n")


def main() -> int:
    mye = openpyxl.load_workbook(CACHE / "mye24.xlsx", read_only=True, data_only=True)
    checks: list[str] = []
    problems = 0

    # ---- people by region, sex and age
    population = []
    totals = {}
    for sex, sheet in (("female", "MYE2 - Females"), ("male", "MYE2 - Males")):
        table = rows_of(mye[sheet])
        header = table["header"]
        ages = [str(a) for a in range(TOP_AGE)] + [f"{TOP_AGE}+"]
        columns = [header.index(a) for a in ages]
        for name, code, _ in REGIONS:
            row = table[code]
            people = [int(row[c]) for c in columns]
            for age, n in enumerate(people):
                population.append([name, sex, age, n])
            totals[(name, sex)] = (sum(people), int(row[header.index("All ages")]))
        uk_row = table[UK]
        totals[("uk", sex)] = (sum(n for r, s, _, n in population if s == sex), int(uk_row[header.index("All ages")]))
    write_csv(OUT / "population.csv", ["region", "sex", "age", "people"], population)

    checks.append("## Cells add up to the published totals\n\n| Area | Sex | Sum of ages | Published | Difference |\n|---|---|---:|---:|---:|")
    for (area, sex), (summed, published) in totals.items():
        checks.append(f"| {area} | {sex} | {summed:,} | {published:,} | {summed - published:,} |")
        problems += summed != published

    # ---- components of change, mid-2023 to mid-2024
    table = rows_of(mye["MYE3"])
    h = table["header"]
    col = {name: h.index(name) for name in ("Estimated Population mid-2023", "Births", "Deaths", "Internal Migration Net",
                                            "International Migration Net", "Other", "Estimated Population mid-2024")}
    change = []
    checks.append("\n## Each region's change adds up\n\nmid-2023 + births - deaths + net internal + net international + other = mid-2024\n\n"
                  "| Region | mid-2023 | Births | Deaths | Internal | International | Other | mid-2024 | Residual |\n"
                  "|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for name, code, _ in REGIONS:
        r = table[code]
        v = {k: int(r[i]) for k, i in col.items()}
        residual = (v["Estimated Population mid-2023"] + v["Births"] - v["Deaths"] + v["Internal Migration Net"]
                    + v["International Migration Net"] + v["Other"] - v["Estimated Population mid-2024"])
        problems += residual != 0
        change.append([name, v["Estimated Population mid-2023"], v["Births"], v["Deaths"], v["Internal Migration Net"],
                       v["International Migration Net"], v["Other"], v["Estimated Population mid-2024"]])
        checks.append(f"| {name} | {v['Estimated Population mid-2023']:,} | {v['Births']:,} | {v['Deaths']:,} | "
                      f"{v['Internal Migration Net']:,} | {v['International Migration Net']:,} | {v['Other']:,} | "
                      f"{v['Estimated Population mid-2024']:,} | {residual:,} |")
        mid2024 = sum(totals[(name, s)][1] for s in ("female", "male"))
        problems += mid2024 != v["Estimated Population mid-2024"]
    write_csv(OUT / "population_change.csv",
              ["region", "population_2023", "births", "deaths", "internal_net", "international_net", "other",
               "population_2024"], change)

    # ---- life table, 2022-2024
    life = openpyxl.load_workbook(CACHE / "lifetables.xlsx", read_only=True, data_only=True)
    sheet = life["2022-2024"]
    rows = list(sheet.iter_rows(values_only=True))
    header_at = next(i for i, r in enumerate(rows) if r and r[0] == "age")
    header = rows[header_at]
    starts = {"male": 0, "female": header.index("age", 1)}
    table_rows = [r for r in rows[header_at + 1:] if r and isinstance(r[0], (int, float))]
    qx_rows = []
    for sex in ("female", "male"):
        s = starts[sex]
        by_age = {int(r[s]): r[s: s + 6] for r in table_rows if r[s] is not None}
        for age in range(TOP_AGE):
            qx_rows.append([sex, age, by_age[age][2]])
        e90 = float(by_age[TOP_AGE][5])
        qx_rows.append([sex, TOP_AGE, round(1 - math.exp(-1 / e90), 6)])
    write_csv(OUT / "life_table.csv", ["sex", "age", "qx"], qx_rows)

    # ---- provenance
    sources = []
    for file, title in (("mye24.xlsx", "Population estimates for the UK, England, Wales, Scotland and Northern Ireland: mid-2024 (tables MYE2, MYE3)"),
                        ("lifetables.xlsx", "National life tables, United Kingdom, 2022 to 2024")):
        data = (CACHE / file).read_bytes()
        meta_path = CACHE / file.replace(".xlsx", ".meta.json")
        retrieved = json.loads(meta_path.read_text())["retrieved"] if meta_path.exists() else "unknown"
        sources.append(f"| {title} | `{file}` | {retrieved} | `{hashlib.sha256(data).hexdigest()[:16]}` |")
    text = ["# UK population data", "",
            "Generated by `python tools/uk/population.py`; do not edit. Source: Office for National Statistics,",
            "licensed under the Open Government Licence v3.0.", "",
            "| Source | Cached file | Retrieved | SHA-256 (first 16) |", "|---|---|---|---|", *sources, "", *checks, ""]
    (OUT / "POPULATION.md").write_text("\n".join(text), encoding="utf-8", newline="\n")
    people = sum(r[3] for r in population)
    print(f"population.csv: {len(population)} cells, {people:,} people; life_table.csv: {len(qx_rows)} rows; "
          f"{problems} check(s) failed")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
