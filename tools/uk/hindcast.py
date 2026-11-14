"""The UK hindcast (docs/S3-PLAN.md, milestone S3.4).

    python tools/uk/hindcast.py            run and write models/uk/hindcast/
    python tools/uk/hindcast.py --check    run and fail if the committed results differ

The model is calibrated to 2004 (tools/uk/calibrate.py with base year 2004) and run month
by month from January 2005 to December 2024. What the model takes as given follows the
published figures:

- policy: each year's spending bills, average income tax and National Insurance rates
  and council tax, read off that year's accounts by the same derivation that calibrates
  the model (calibrate.derive); VAT and corporation tax at their statutory rates, month
  by month;
- the labour force (people in work plus the unemployed), interpolated through the annual
  averages;
- world demand, so that exports equal the published figure each year;
- the market yield on new gilts: the 10 year gilt yield, quarter by quarter.

Everything else is the model's own: employment and unemployment, wages, household
income, imports, tax receipts, debt interest, borrowing and debt. Three runs are made:

- A, the model's own behaviour: households spend, and firms invest, fixed shares of
  income and sales, and prices come from the Phillips curve;
- B, the main run: the shares the model holds fixed follow the published figures: the
  share of income households spend, and business investment, imports and the private
  pay bill as shares of sales. This is how the crises of 2008-09 and 2020 enter (the
  model has no financial sector, no pandemic and no exchange rate);
- C, a diagnostic: B with prices following the published GDP deflator and pay per
  employee following compensation per person in work, to show what is left of each
  miss once prices and pay are right.

The model's first month is its base year's average month, the middle of 2004, so the run
starts in July 2004 and the comparison from January 2005. Annual figures are placed in
the middle of their year and interpolated month by month.

The results are compared, year by year, with the bands proposed in docs/S3-PLAN.md
before any run.
"""

from __future__ import annotations

import argparse
import csv
import io
import math
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "oracle"))
sys.path.insert(0, str(HERE))

import calibrate  # noqa: E402
from polisim_oracle import Simulation, load_model  # noqa: E402

BASE = "2004"
FIRST, LAST = 2005, 2024
LEAD = 6  # July to December 2004, before the comparison starts
STEPS = LEAD + 12 * (LAST - FIRST + 1)
SEED = 2005
OUT = ROOT / "models" / "uk" / "hindcast"

# The bands of docs/S3-PLAN.md: (what, limit, unit, years it applies to)
BANDS = [
    ("Nominal GDP", 5.0, "% of outturn", "every year"),
    ("Public sector net borrowing", 2.0, "points of GDP", "every year"),
    ("Unemployment rate", 1.5, "points", "every year"),
    ("Public sector net debt", 10.0, "points of GDP", "after 10 years (end of 2014)"),
]


def quarter_values(name: str) -> dict[str, float]:
    with open(ROOT / "models/uk/data/quarterly.csv", newline="", encoding="utf-8") as handle:
        return {row["period"]: float(row[name]) for row in csv.DictReader(handle) if row[name] != ""}


def through_years(values: dict[int, float], x: float, log: bool = False) -> float:
    """A smooth monthly path through annual figures: each year's figure is placed in the
    middle of its year (month 5.5, counting January 2005 as 0) and months in between are
    interpolated, linearly or in logs; beyond the last year the last segment continues.
    Annual figures stepped in every January would jump a whole year's growth at once."""
    points = sorted((12 * (year - FIRST) + 5.5, value) for year, value in values.items())
    i = max([k for k in range(len(points) - 1) if points[k][0] <= x] or [0])
    i = min(i, len(points) - 2)
    (x0, y0), (x1, y1) = points[i], points[i + 1]
    if log:
        return math.exp(math.log(y0) + (math.log(y1) - math.log(y0)) * (x - x0) / (x1 - x0))
    return y0 + (y1 - y0) * (x - x0) / (x1 - x0)


def run(model_dir: Path, behaviour: bool, follow_prices: bool) -> list[dict]:
    """One hindcast run; returns the monthly result rows from January 2005. With
    `follow_prices`, prices and private pay follow the published figures."""
    data = calibrate.load_data()
    a = calibrate.load_assumptions()
    model = load_model(model_dir)
    # Exogenous indices do not depend on anything the inputs change, so one plain run
    # gives the trend and world indices each month reads (their start-of-month values).
    plain = Simulation(model, seed=SEED).run(STEPS)
    start = {name: [1.0] + [row[name] for row in plain[:-1]] for name in ("trend_index", "world_index")}
    first = plain[0]
    exports_base = Simulation(model, seed=SEED).rt.S["exports_base"]  # pence a month
    gilt_assumption = Simulation(model, seed=SEED).rt.S["gilt_yield"]
    growth = Simulation(model, seed=SEED).rt.S["labour_force_growth"]
    inflation_target = Simulation(model, seed=SEED).rt.S["inflation_target"]
    slope = Simulation(model, seed=SEED).rt.S["phillips_slope"]
    natural = Simulation(model, seed=SEED).rt.S["natural_unemployment"]
    del first

    gilts = quarter_values("gilt_yield_10y")
    years = range(int(BASE), LAST + 1)
    deflator = {y: float(data[str(y)]["gdp_deflator"] / data[BASE]["gdp_deflator"]) for y in years}
    labour_force = {y: float(data[str(y)]["employment"] + data[str(y)]["unemployed"]) * 1000 for y in years}
    exports_path = {y: float(data[str(y)]["exports"]) * 1e8 / 12 for y in years}  # pence a month
    derived = {y: calibrate.derive(str(y), data, a) for y in years}
    policies = {y: calibrate.policy(v) for y, v in derived.items()}
    base = derived[int(BASE)]
    spending_shift = {y: float(v.income_share - base.income_share) for y, v in derived.items()}
    investment_demand = {y: float((v.business_investment / v.private_demand)
                                  / (base.business_investment / base.private_demand)) for y, v in derived.items()}
    import_propensity = {y: float((v.imports / v.private_demand) / (base.imports / base.private_demand))
                         for y, v in derived.items()}
    labour_share = {y: float((v.private_pay / v.private_demand) / (base.private_pay / base.private_demand))
                    for y, v in derived.items()}
    pay = {y: float(v.compensation / (v.private_employment + v.public_employment)
                    / (base.compensation / (base.private_employment + base.public_employment))) for y, v in derived.items()}
    productivity = Simulation(model, seed=SEED).rt.S["productivity_growth"]

    sim = Simulation(model, seed=SEED)
    lf_before = sim.rt.S["labour_force"]
    pay_start = sim.rt.S["private_pay_per_worker"]
    rows: list[dict] = []
    for t in range(STEPS):
        x = t - LEAD  # months since the start of January 2005
        year, month = FIRST + x // 12, x % 12 + 1
        trend = start["trend_index"][t]
        settings: dict[str, object] = {}
        for name in policies[year]:
            value = through_years({y: float(p[name]) for y, p in policies.items()}, x)
            settings[name] = value if name.endswith("_rate") else round(value / trend, 2)
        settings["vat_rate"] = float(calibrate.rate_in_force(a, "vat_rate", year, month))
        settings["corporation_tax_rate"] = float(calibrate.rate_in_force(a, "corporation_tax_rate", year, month))
        settings["export_demand"] = through_years(exports_path, x) / (exports_base * start["world_index"][t])
        settings["labour_force_shock"] = through_years(labour_force, x + 0.5, log=True) / lf_before - 1.0 - growth
        if behaviour:
            settings["spending_shift"] = through_years(spending_shift, x)
            settings["investment_demand"] = through_years(investment_demand, x)
            settings["import_propensity"] = through_years(import_propensity, x)
            settings["labour_share"] = through_years(labour_share, x)
        lf_before = lf_before * (1.0 + growth + settings["labour_force_shock"])
        quarter = f"{year} Q{(month - 1) // 3 + 1}"
        settings["gilt_yield_shift"] = gilts[quarter] / 100 - gilt_assumption
        if follow_prices:
            # The price level the deflator gives for the end of this month (log-linear
            # through annual averages placed mid-year), reached by a shock on top of the
            # model's own inflation, which uses last month's unemployment (this month's
            # differs by a hair, and the next month's shock corrects it).
            target = through_years(deflator, x + 0.5, log=True)
            before = rows[-1]["price_index"] if rows else 1.0
            unemployment = rows[-1]["unemployment_rate"] if rows else sim_unemployment(sim)
            own = inflation_target + slope * (natural - unemployment)
            settings["inflation_shock"] = target / before - 1.0 - own
            # Pay per employee likewise, given this month's inflation (as targeted).
            pay_before = rows[-1]["private_pay_per_worker"] if rows else sim.rt.S["private_pay_per_worker"]
            pay_target = through_years(pay, x + 0.5, log=True) * pay_start
            settings["pay_shock"] = pay_target / pay_before - 1.0 - productivity - (target / before - 1.0)
        sim.commands[t] = settings
        rows.append(sim.step())
    return rows[LEAD:]


def sim_unemployment(sim: Simulation) -> float:
    s = sim.rt.S
    return 1.0 - (s["private_employment"] + s["public_pay_bill"] / s["public_pay_per_worker"]) / s["labour_force"]


def annual(rows: list[dict]) -> dict[int, dict[str, float]]:
    out = {}
    for year in range(FIRST, LAST + 1):
        months = rows[12 * (year - FIRST): 12 * (year - FIRST + 1)]
        gdp = sum(r["gdp"] for r in months) / 1e8  # £ million
        out[year] = {
            "gdp": gdp,
            "real_gdp": sum(r["real_gdp"] for r in months) / 1e8,
            "borrowing": -sum(r["budget_balance"] for r in months) / 1e8,
            "unemployment": sum(r["unemployment_rate"] for r in months) / 12 * 100,
            "debt": months[-1]["public_debt"] / 1e8,
            "receipts": sum(r["public_receipts"] for r in months) / 1e8,
            "spending": sum(r["public_spending"] for r in months) / 1e8,
            "interest": sum(r["gilt_interest_banks"] + r["gilt_interest_abroad"] for r in months) / 1e8,
            "price": sum(r["price_index"] for r in months) / 12,
            "employment": sum(r["employment"] for r in months) / 12 / 1000,
        }
    return out


def outturn() -> dict[int, dict[str, float]]:
    data = calibrate.load_data()
    base = data[BASE]
    out = {}
    from_borrowing = float(base["ps_net_debt"]) * 1000
    for year in range(FIRST, LAST + 1):
        d = data[str(year)]
        # Debt grows by borrowing and by financial transactions (loans to banks and
        # students, asset purchases), which borrowing leaves out and the model has not.
        from_borrowing += float(-d["ps_net_borrowing"])
        out[year] = {
            "debt_from_borrowing": from_borrowing,
            "gdp": float(d["gdp"]),
            "real_gdp": float(d["gdp_real"] / base["gdp_real"] * base["gdp"]),
            "borrowing": float(-d["ps_net_borrowing"]),
            "unemployment": float(d["unemployment_rate"]),
            "debt": float(d["ps_net_debt"]) * 1000,
            "receipts": float(d["ps_current_receipts"]),
            "interest": float(d["ps_interest"]),
            "price": float(d["gdp_deflator"] / base["gdp_deflator"]),
            "employment": float(d["employment"]),
        }
    return out


def compare(model: dict, actual: dict) -> dict[int, dict[str, float]]:
    """Errors by year: GDP in % of outturn, the rest in points."""
    out = {}
    for year in model:
        m, o = model[year], actual[year]
        out[year] = {
            "gdp": (m["gdp"] / o["gdp"] - 1) * 100,
            "real_gdp": (m["real_gdp"] / o["real_gdp"] - 1) * 100,
            "price": (m["price"] / o["price"] - 1) * 100,
            "borrowing": (m["borrowing"] / m["gdp"] - o["borrowing"] / o["gdp"]) * 100,
            "unemployment": m["unemployment"] - o["unemployment"],
            "debt": (m["debt"] / m["gdp"] - o["debt"] / o["gdp"]) * 100,
            "debt_from_borrowing": (m["debt"] / m["gdp"] - o["debt_from_borrowing"] / o["gdp"]) * 100,
            "receipts": (m["receipts"] / m["gdp"] - o["receipts"] / o["gdp"]) * 100,
            "interest": (m["interest"] / m["gdp"] - o["interest"] / o["gdp"]) * 100,
        }
    return out


def verdicts(errors: dict[int, dict[str, float]]) -> list[tuple[str, str, str]]:
    def worst(key):
        year = max(errors, key=lambda y: abs(errors[y][key]))
        return year, errors[year][key]

    out = []
    for (what, limit, unit, when), key in zip(BANDS, ("gdp", "borrowing", "unemployment", "debt")):
        if key == "debt":
            value = errors[2014][key]
            ok = abs(value) <= limit
            detail = (f"{value:+.1f} at the end of 2014; {errors[2014]['debt_from_borrowing']:+.1f} against debt "
                      "built from borrowing alone (published debt less financial transactions)")
        else:
            missed = [y for y in errors if abs(errors[y][key]) > limit]
            year, value = worst(key)
            ok = not missed
            detail = f"largest {value:+.1f} in {year}" + (f"; outside in {len(missed)} of {len(errors)} years ({_years(missed)})" if missed else "")
        out.append((f"{what}: within {limit:g} {unit}, {when}", "met" if ok else "missed", detail))
    return out


def _years(years: list[int]) -> str:
    """2008, 2009, 2010, 2015 -> 2008-2010, 2015."""
    spans, start = [], None
    for i, y in enumerate(years):
        if start is None:
            start = y
        if i + 1 == len(years) or years[i + 1] != y + 1:
            spans.append(str(start) if start == y else f"{start}-{y}")
            start = None
    return ", ".join(spans)


def table(model: dict, actual: dict, errors: dict) -> list[str]:
    lines = ["| Year | GDP £bn, model | outturn | error % | real GDP error % | prices error % | "
             "borrowing % GDP, model | outturn | unemployment %, model | outturn | debt % GDP, model | outturn | "
             "from borrowing alone |",
             "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for year in model:
        m, o, e = model[year], actual[year], errors[year]
        lines.append(
            f"| {year} | {m['gdp'] / 1000:,.0f} | {o['gdp'] / 1000:,.0f} | {e['gdp']:+.1f} | {e['real_gdp']:+.1f} | "
            f"{e['price']:+.1f} | {m['borrowing'] / m['gdp'] * 100:.1f} | {o['borrowing'] / o['gdp'] * 100:.1f} | "
            f"{m['unemployment']:.1f} | {o['unemployment']:.1f} | {m['debt'] / m['gdp'] * 100:.0f} | "
            f"{o['debt'] / o['gdp'] * 100:.0f} | {o['debt_from_borrowing'] / o['gdp'] * 100:.0f} |")
    return lines


def report() -> tuple[str, str]:
    """The report (Markdown) and the yearly results (CSV)."""
    actual = outturn()
    sections, csv_rows = [], []
    with tempfile.TemporaryDirectory() as folder:
        model_dir = Path(folder) / "uk"
        calibrate.write_model(BASE, model_dir)
        # Lever ranges are guardrails for players, set around the base year; history went
        # beyond them (subsidies in 2020 were furlough), so the hindcast model has none.
        calibration = model_dir / "calibration.toml"
        lines = calibration.read_text(encoding="utf-8").splitlines()
        calibration.write_text("\n".join(x for x in lines if not x.startswith("range = ")) + "\n", encoding="utf-8")
        for label, behaviour, follow, title in (
                ("B", True, False, "Run B (main): the shares the model holds fixed follow the published figures"),
                ("A", False, False, "Run A: the model's own behaviour throughout"),
                ("C", True, True, "Run C (diagnostic): run B with prices and pay that follow the published figures")):
            rows = run(model_dir, behaviour, follow)
            model = annual(rows)
            errors = compare(model, actual)
            sections.append(f"## {title}\n")
            sections.append("| Band | Result | Detail |\n|---|---|---|")
            for band, result, detail in verdicts(errors):
                sections.append(f"| {band} | **{result}** | {detail} |")
            sections.append("")
            sections.extend(table(model, actual, errors))
            sections.append("")
            for year in model:
                csv_rows.append({"run": label, "year": year,
                                 **{f"model_{k}": f"{v:.3f}" for k, v in model[year].items()},
                                 **{f"error_{k}": f"{v:.3f}" for k, v in errors[year].items()}})
    head = [
        "# UK hindcast, 2005 to 2024",
        "",
        "Generated by `python tools/uk/hindcast.py`; do not edit. The method is in the script's",
        "docstring and the reading of the results in `models/uk/README.md`. The model is",
        "calibrated to 2004 and run monthly from the middle of 2004; policy, the labour force,",
        "exports and the 10 year gilt yield follow the published figures in every run. Errors",
        "are model minus outturn. Debt is at the end of the year as a share of that year's GDP;",
        "\"from borrowing alone\" is the 2004 debt plus each year's published borrowing, which",
        "leaves out the financial transactions (loans to banks and students, asset purchases)",
        "the model does not have.",
        "",
    ]
    text = "\n".join(head + sections).rstrip() + "\n"
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=list(csv_rows[0]), lineterminator="\n")
    writer.writeheader()
    writer.writerows(csv_rows)
    return text, buffer.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="fail if the committed results differ")
    args = parser.parse_args()
    text, table_csv = report()
    files = {OUT / "REPORT.md": text, OUT / "results.csv": table_csv}
    if args.check:
        stale = [p for p, content in files.items() if not p.exists() or p.read_text(encoding="utf-8") != content]
        if stale:
            print("hindcast results differ from the committed files: " + ", ".join(str(p.relative_to(ROOT)) for p in stale))
            return 1
        print("hindcast reproduces the committed results")
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    for path, content in files.items():
        path.write_text(content, encoding="utf-8", newline="\n")
    print(text.split("## Run A")[0])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
