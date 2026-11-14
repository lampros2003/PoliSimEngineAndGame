"""The United Kingdom's data pipeline (stage S3.0).

    python tools/uk/pipeline.py fetch      download every dataset in sources.toml into .cache/uk/
                                           (or only those named: fetch giltyield)
    python tools/uk/pipeline.py extract    write models/uk/data/ from the cached downloads
    python tools/uk/pipeline.py check      test the accounting identities and write CHECKS.md
    python tools/uk/pipeline.py all        all three

`extract` and `check` read only the cache, so with the same downloads they rebuild every
committed file byte for byte. Values are copied as the publisher wrote them; the only
arithmetic is averaging the Bank of England's monthly series (Bank Rate, the 10 year
gilt yield) into quarters and years, done in exact decimals.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
import sys
import tomllib
import urllib.request
from datetime import datetime, timezone
from decimal import ROUND_HALF_EVEN, Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CACHE = ROOT / ".cache" / "uk"
OUT = ROOT / "models" / "uk" / "data"
FIRST_YEAR = 1995
BASE_YEAR = 2024
USER_AGENT = "Mozilla/5.0 (compatible; PoliSim data pipeline)"


def load_toml(name: str) -> dict:
    return tomllib.loads((HERE / name).read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------- fetch

def fetch(only: list[str] | None = None) -> None:
    """Download every dataset, or only those named (so adding a source does not pull new
    releases of the others, which would change every derived figure)."""
    CACHE.mkdir(parents=True, exist_ok=True)
    datasets = load_toml("sources.toml")["dataset"]
    unknown = [name for name in only or [] if name not in datasets]
    if unknown:
        raise SystemExit(f"no dataset named {', '.join(unknown)} in sources.toml")
    for name, spec in datasets.items():
        if only and name not in only:
            continue
        request = urllib.request.Request(spec["url"], headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=600) as response:
            data = response.read()
        target = CACHE / spec.get("file", f"{name}.csv")
        target.write_bytes(data)
        meta = {"retrieved": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
        (CACHE / f"{target.stem}.meta.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")
        print(f"fetched {name}: {len(data):,} bytes")


# ---------------------------------------------------------------------------- reading

def read_ons(path: Path) -> tuple[dict[str, dict[str, str]], dict[str, dict[str, str]]]:
    """Returns ({code: {period: value}}, {code: {field: text}}) for an ONS time-series CSV."""
    rows = list(csv.reader(io.StringIO(path.read_text(encoding="utf-8", errors="replace"))))
    header = {row[0]: row for row in rows[:7]}
    codes = header["CDID"]
    info = {}
    for i in range(1, len(codes)):
        info[codes[i]] = {k: header[k][i] for k in header if i < len(header[k])}
    values: dict[str, dict[str, str]] = {code: {} for code in codes[1:]}
    for row in rows[7:]:
        period = row[0].strip()
        for i in range(1, min(len(row), len(codes))):
            if row[i].strip() != "":
                values[codes[i]][period] = row[i].strip()
    return values, info


MONTHS = {m: i for i, m in enumerate(["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], 1)}


def read_boe_monthly(path: Path, code: str) -> tuple[dict[str, dict[str, str]], dict[str, dict[str, str]]]:
    """Bank of England monthly series: averages of its months for quarters and years."""
    rows = list(csv.reader(io.StringIO(path.read_text(encoding="utf-8", errors="replace"))))
    column = rows[0].index(code)
    by_month: dict[tuple[int, int], Decimal] = {}
    for row in rows[1:]:
        if len(row) <= column or row[column].strip() == "":
            continue
        _, month, year = row[0].split()
        by_month[(int(year), MONTHS[month])] = Decimal(row[column].strip())
    out: dict[str, str] = {}
    quantum = Decimal("0.0001")
    years = sorted({y for y, _ in by_month})
    for year in years:
        months = [by_month.get((year, m)) for m in range(1, 13)]
        if all(v is not None for v in months):
            out[str(year)] = str((sum(months) / 12).quantize(quantum, ROUND_HALF_EVEN))
        for q in range(4):
            part = months[3 * q:3 * q + 3]
            if all(v is not None for v in part):
                out[f"{year} Q{q + 1}"] = str((sum(part) / 3).quantize(quantum, ROUND_HALF_EVEN))
    return {code: out}, {code: {"Title": "Bank Rate, monthly average", "CDID": code}}


def load_all() -> tuple[dict, dict, dict]:
    sources = load_toml("sources.toml")["dataset"]
    values, info = {}, {}
    for name, spec in sources.items():
        if spec["format"] in ("ons_xlsx", "table"):
            continue  # workbooks and tables: read by tools/uk/population.py, elections.py and their kind
        path = CACHE / f"{name}.csv"
        if not path.exists():
            sys.exit(f"{path} is missing: run `python tools/uk/pipeline.py fetch` first")
        if spec["format"] == "ons_timeseries":
            values[name], info[name] = read_ons(path)
        else:
            series = [s for s in load_toml("series.toml")["series"].values() if s["dataset"] == name]
            values[name], info[name] = read_boe_monthly(path, series[0]["code"])
    return sources, values, info


# ---------------------------------------------------------------------------- extract

def periods(kind: str, last_year: int) -> list[str]:
    if kind == "annual":
        return [str(y) for y in range(FIRST_YEAR, last_year + 1)]
    return [f"{y} Q{q}" for y in range(FIRST_YEAR, last_year + 1) for q in range(1, 5)]


def extract() -> None:
    sources, values, info = load_all()
    catalogue = load_toml("series.toml")["series"]
    missing = [f"{name} ({s['dataset']} {s['code']})" for name, s in catalogue.items() if s["code"] not in values[s["dataset"]]]
    if missing:
        sys.exit("series not found in the downloads: " + ", ".join(missing))
    last_year = max(int(p) for s in catalogue.values() for p in values[s["dataset"]][s["code"]] if p.isdigit())
    OUT.mkdir(parents=True, exist_ok=True)
    for kind, filename in (("annual", "annual.csv"), ("quarterly", "quarterly.csv")):
        rows = []
        for period in periods(kind, last_year):
            row = [period] + [values[s["dataset"]][s["code"]].get(period, "") for s in catalogue.values()]
            if any(cell != "" for cell in row[1:]):
                rows.append(row)
        buffer = io.StringIO()
        writer = csv.writer(buffer, lineterminator="\n")
        writer.writerow(["period"] + list(catalogue))
        writer.writerows(rows)
        (OUT / filename).write_text(buffer.getvalue(), encoding="utf-8", newline="\n")
        print(f"wrote {filename}: {len(rows)} periods x {len(catalogue)} series")

    lines = ["# Provenance of every file in this folder. Generated by tools/uk/pipeline.py; do not edit.", ""]
    lines += ["[attribution]",
              'text = "Contains public sector information licensed under the Open Government Licence v3.0. '
              'Source: Office for National Statistics, Bank of England and HM Treasury. Contains Parliamentary information '
              'licensed under the Open Parliament Licence v3.0."', ""]
    for name, spec in sources.items():
        meta = json.loads((CACHE / f"{Path(spec.get('file', name + '.csv')).stem}.meta.json").read_text(encoding="utf-8"))
        release = next((i.get("Release Date", "") for i in info.get(name, {}).values() if i.get("Release Date")), "")
        lines += [f"[dataset.{name}]"]
        for key in ("title", "publisher", "url", "page", "licence", "attribution"):
            lines.append(f"{key} = {json.dumps(spec[key])}")
        lines += [f"release_date = {json.dumps(release)}", f"retrieved = {json.dumps(meta['retrieved'])}",
                  f"sha256 = {json.dumps(meta['sha256'])}", ""]
    for name, s in catalogue.items():
        title = info[s["dataset"]][s["code"]].get("Title", "")
        lines += [f"[series.{name}]", f"dataset = {json.dumps(s['dataset'])}", f"code = {json.dumps(s['code'])}",
                  f"unit = {json.dumps(s['unit'])}", f"published_title = {json.dumps(title)}", ""]
    (OUT / "MANIFEST.toml").write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print("wrote MANIFEST.toml")


# ---------------------------------------------------------------------------- check

def table(path: Path) -> dict[str, dict[str, Decimal]]:
    rows = list(csv.DictReader(path.read_text(encoding="utf-8").splitlines()))
    return {r["period"]: {k: Decimal(v) for k, v in r.items() if k != "period" and v != ""} for r in rows}


IDENTITIES = [
    ("GDP equals its expenditure components",
     "gdp - (household_consumption + npish_consumption + government_consumption + investment + inventories + valuables + exports - imports)",
     lambda v: v["gdp"] - (v["household_consumption"] + v["npish_consumption"] + v["government_consumption"] + v["investment"]
                           + v["inventories"] + v["valuables"] + v["exports"] - v["imports"])),
    ("Sector balances sum to zero",
     "households + non-financial corporations + financial corporations + government + rest of world",
     lambda v: v["net_lending_households"] + v["net_lending_nonfinancial_corporations"] + v["net_lending_financial_corporations"]
     + v["net_lending_government"] + v["net_lending_rest_of_world"]),
    ("Public sector net borrowing equals the current budget less net investment",
     "receipts - current expenditure - depreciation + net investment (as published) - net borrowing (as published)",
     lambda v: v["ps_current_receipts"] - v["ps_current_expenditure"] - v["ps_depreciation"] + v["ps_net_investment"]
     - v["ps_net_borrowing"]),
]


def check() -> int:
    annual = table(OUT / "annual.csv")
    years = [y for y in sorted(annual) if int(y) >= 2000]
    lines = ["# Checks on the UK data", "",
             "Generated by `python tools/uk/pipeline.py check`. Each identity is computed from the",
             "published figures in `annual.csv`; the residual is in £ million. A residual of 0 means",
             "the published accounts close exactly.", ""]
    failed = 0
    for title, formula, rule in IDENTITIES:
        lines += [f"## {title}", "", f"Residual = {formula}", "", "| Year | Residual |", "|---|---:|"]
        worst = Decimal(0)
        for year in years:
            try:
                residual = rule(annual[year])
            except KeyError:
                continue
            worst = max(worst, abs(residual))
            lines.append(f"| {year} | {residual:,} |")
            if year == str(BASE_YEAR) and residual != 0:
                failed += 1
        lines += ["", f"Largest absolute residual since 2000: {worst:,}.", ""]
    base = annual[str(BASE_YEAR)]
    lines += [f"## Base year {BASE_YEAR}", "", "| Series | Value |", "|---|---:|"]
    for name in sorted(base):
        lines.append(f"| {name} | {base[name]:,} |")
    (OUT / "CHECKS.md").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote CHECKS.md; {failed} identity(ies) do not close in {BASE_YEAR}")
    return 1 if failed else 0


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else "all"
    if command in ("fetch", "all"):
        fetch(sys.argv[2:] if command == "fetch" else None)
    if command in ("extract", "all"):
        extract()
    if command in ("check", "all"):
        return check()
    if command not in ("fetch", "extract", "check", "all"):
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
