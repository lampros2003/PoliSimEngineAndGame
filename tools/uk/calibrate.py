"""Derive the UK model's parameters and lever settings from one year's accounts.

    python tools/uk/calibrate.py                            base year 2024, into models/uk
    python tools/uk/calibrate.py --base-year 2004 --out DIR  another base year, elsewhere

Reads models/uk/data/annual.csv and tools/uk/assumptions.toml, writes calibration.toml,
model.toml and economy.toml (the last two from tools/uk/template/), and prints the
base-year accounts the model reproduces. Every number written is either a published
figure for the base year (as one twelfth, for a month), an assumption, or derived from
those so that the first month of a run equals one twelfth of the base year.

`derive(year)` does the derivation for any year; the hindcast (tools/uk/hindcast.py) uses
it to read each year's policy settings off that year's accounts.
"""

from __future__ import annotations

import argparse
import csv
import math
import tomllib
from fractions import Fraction
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
DEFAULT_BASE = "2024"
STOCKS_YEAR = "2024"  # the year the opening stocks and money amounts in assumptions.toml describe
MONTHS = 12


def money(pounds_million: Fraction | float | int) -> int:
    """£ million a year or a stock -> whole pounds, rounded half to even."""
    return round(Fraction(pounds_million) * 1_000_000)


def monthly(annual_million: Fraction | int) -> int:
    return money(Fraction(annual_million) / MONTHS)


def pounds_and_pence(value: Fraction) -> str:
    """An amount in pounds, to the penny, as TOML: 450 or 270.93."""
    pence = round(value * 100)
    return str(pence // 100) if pence % 100 == 0 else f"{pence / 100:.2f}"


def load_data() -> dict[str, dict[str, Fraction]]:
    rows = csv.DictReader((ROOT / "models/uk/data/annual.csv").read_text(encoding="utf-8").splitlines())
    return {r["period"]: {k: Fraction(v) for k, v in r.items() if k != "period" and v != ""} for r in rows}


def load_assumptions() -> dict:
    return tomllib.loads((HERE / "assumptions.toml").read_text(encoding="utf-8"))


def rate_in_force(a: dict, name: str, year: int, month: int) -> Fraction:
    """A statutory rate on the 15th of a month, from the dated schedule in assumptions.toml."""
    day = f"{year:04d}-{month:02d}-15"
    rate = None
    for start, value in a["statutory"][name]:
        if start <= day:
            rate = Fraction(str(value))
    if rate is None:
        raise SystemExit(f"assumptions.toml: no {name} in force on {day}")
    return rate


def year_average(a: dict, name: str, year: str) -> Fraction:
    return sum(rate_in_force(a, name, int(year), m) for m in range(1, 13)) / MONTHS


def derive(year: str, data: dict | None = None, a: dict | None = None) -> SimpleNamespace:
    """Every quantity the model needs, from one year's published accounts (£ million a year
    unless named otherwise) and the assumptions."""
    data = data if data is not None else load_data()
    a = a if a is not None else load_assumptions()
    d = data[year]
    st, be = a["stocks"], a["behaviour"]
    v = SimpleNamespace(year=year)

    # Stocks and money amounts in the assumptions describe STOCKS_YEAR; another year's are
    # scaled by nominal GDP (stocks) or by the GDP deflator (amounts per person).
    v.stock_scale = d["gdp"] / data[STOCKS_YEAR]["gdp"]
    v.price_scale = d["gdp_deflator"] / data[STOCKS_YEAR]["gdp_deflator"]
    v.stocks = {k: Fraction(st[k]) * v.stock_scale for k in
                ("household_deposits", "firm_deposits", "rest_of_world_deposits", "government_deposits", "firm_bank_loans")}

    # ---- published figures
    v.consumption = d["household_consumption"] + d["npish_consumption"]
    v.public_pay = d["cg_staff_costs"] + d["lg_staff_costs"]
    v.procurement = d["cg_procurement"] + d["lg_procurement"]
    v.benefits = d["ps_social_benefits"]
    v.interest = d["ps_interest"]
    v.subsidies = d["ps_subsidies"]
    v.other_current = d["ps_current_expenditure"] - (v.public_pay + v.procurement + v.benefits + v.interest + v.subsidies)
    v.public_investment = d["ps_depreciation"] - d["ps_net_investment"]  # gross: depreciation plus net
    v.income_tax, v.nics, v.vat, v.corp_tax = d["income_tax"], d["social_contributions"], d["vat"], d["corporation_tax"]
    v.council = d["council_tax"]
    v.production_taxes = d["taxes_on_production"] - v.vat
    v.receipts = d["ps_current_receipts"]
    v.other_receipts = v.receipts - (v.income_tax + v.nics + v.vat + v.corp_tax + v.production_taxes + v.council)
    v.debt = d["ps_net_debt"] * 1000  # £ billion -> £ million
    v.exports, v.imports = d["exports"], d["imports"]
    v.compensation = d["compensation_of_employees"]
    v.private_pay = v.compensation - v.public_pay
    v.disposable_income = d["household_disposable_income"]
    v.gdp = d["gdp"]
    v.borrowing = -d["ps_net_borrowing"]
    # Business investment: whole-economy investment less public investment and an estimate
    # of households' dwellings (taken as 21% of investment, the share of new dwellings in
    # 2024's total; refined when the dwellings series joins the pipeline).
    v.dwellings = d["investment"] * Fraction(21, 100)
    v.business_investment = d["investment"] - v.public_investment - v.dwellings
    v.private_demand = (v.consumption + v.dwellings + v.procurement + v.public_investment + v.business_investment
                        + v.exports)

    # ---- employment
    employed = d["employment"] * 1000
    v.unemployed = d["unemployed"] * 1000
    v.labour_force = employed + v.unemployed
    v.pay_per_worker = v.compensation / employed  # £ million a year per person
    v.public_employment = v.public_pay / v.pay_per_worker
    v.private_employment = employed - v.public_employment

    # ---- money and interest
    v.rate = v.interest / v.debt
    v.abroad = Fraction(str(st["gilts_held_abroad"]))
    interest_banks = v.interest * (1 - v.abroad)
    v.payout_ratio = (interest_banks - d["net_lending_financial_corporations"]) / interest_banks

    # ---- households: other income makes disposable income match; transfers outside
    # disposable income (pension adjustment, capital transfers) make net lending match.
    v.benefit_per_unemployed = Fraction(be["benefit_per_unemployed"]) * v.price_scale  # £ a month
    benefit_unemployed = v.benefit_per_unemployed * MONTHS / 1_000_000  # £m a year per person
    v.benefits_other = v.benefits - benefit_unemployed * v.unemployed
    bank_payout = interest_banks * v.payout_ratio
    v.other_income = v.disposable_income - (v.compensation + v.benefits + bank_payout - v.income_tax - v.nics - v.council)
    v.income_tax_rate = v.income_tax / (v.compensation + v.benefits + v.other_income)
    v.nics_rate = v.nics / v.compensation
    v.pension_transfers = d["net_lending_households"] - v.disposable_income + v.consumption + v.dwellings
    v.wealth_share = Fraction(str(be["spend_out_of_savings"]))
    v.income_share = ((v.consumption / MONTHS - v.wealth_share * v.stocks["household_deposits"])
                      / (v.disposable_income / MONTHS))

    # ---- firms and the government's other levies
    v.vat_rate = year_average(a, "vat_rate", year)
    effective = v.vat / v.consumption
    v.vat_base_share = effective / (1 - effective) / v.vat_rate
    v.profit = v.private_demand - v.imports - v.private_pay - v.vat - v.production_taxes - v.other_income
    v.ct_rate = year_average(a, "corporation_tax_rate", year)
    v.ct_base_share = v.corp_tax / (v.ct_rate * v.profit)
    gdp_model = (v.consumption + v.dwellings + v.business_investment + v.public_investment + v.procurement
                 + v.public_pay + v.exports - v.imports)
    v.gdp_adjustment_share = (d["gdp"] - gdp_model) / v.private_demand
    return v


def policy(v: SimpleNamespace) -> dict[str, Fraction]:
    """The year's policy as lever settings in that year's money: £ a month, or rates."""
    return {
        "public_pay_bill": v.public_pay / MONTHS * 1_000_000,
        "procurement_bill": v.procurement / MONTHS * 1_000_000,
        "benefits_bill": v.benefits_other / MONTHS * 1_000_000,
        "benefit_per_unemployed": v.benefit_per_unemployed,
        "public_investment_bill": v.public_investment / MONTHS * 1_000_000,
        "subsidies_bill": v.subsidies / MONTHS * 1_000_000,
        "transfers_abroad_bill": v.other_current / MONTHS * 1_000_000,
        "council_tax_bill": v.council / MONTHS * 1_000_000,
        "income_tax_rate": v.income_tax_rate,
        "nics_rate": v.nics_rate,
    }


def r12(x) -> str:
    return repr(round(float(x), 12))


def growth(annual: float) -> float:
    return round((1 + annual) ** (1 / 12) - 1, 12)


def write_population(out_dir: Path, a: dict) -> dict[str, str]:
    """Format 1: the people block's rates, derived from ONS's mid-2024 population, its
    components of change and the 2022-2024 life table. Returns the template's fills."""
    data_dir = ROOT / "models" / "uk" / "data"

    def table(name):
        return list(csv.DictReader((data_dir / name).read_text(encoding="utf-8").splitlines()))

    pop = {(r["region"], r["sex"], int(r["age"])): float(r["people"]) for r in table("population.csv")}
    change = {r["region"]: r for r in table("population_change.csv")}
    qx = {(r["sex"], int(r["age"])): float(r["qx"]) for r in table("life_table.csv")}
    p = a["population"]
    ages = range(0, 91)
    lo, hi = p["fertility_ages"]
    fertility = {age: (math.exp(-((age - p["fertility_peak_age"]) / p["fertility_spread"]) ** 2) if lo <= age <= hi else 0.0)
                 for age in ages}
    migration = {age: math.exp(-((age - p["migration_peak_age"]) / p["migration_spread"]) ** 2) for age in ages}
    migration_total = 2 * sum(migration.values())
    folder = out_dir / "population"
    folder.mkdir(parents=True, exist_ok=True)
    monthly = {key: 1 - (1 - q) ** (1 / MONTHS) for key, q in qx.items()}
    rows = ["sex,age,mortality,migration_profile"]
    for sex in ("female", "male"):
        for age in ages:
            rows.append(f"{sex},{age},{r12(monthly[(sex, age)])},{r12(migration[age] / migration_total)}")
    (folder / "by_age.csv").write_text("\n".join(rows) + "\n", encoding="utf-8", newline="\n")
    rows = ["age,fertility_profile"] + [f"{age},{r12(fertility[age])}" for age in ages]
    (folder / "by_age_women.csv").write_text("\n".join(rows) + "\n", encoding="utf-8", newline="\n")
    rows = ["region,death_factor,fertility_scale,net_migration"]
    for region, c in change.items():
        # A month's deaths at the life table's rates, times twelve, against the year's deaths.
        expected_deaths = MONTHS * sum(pop[(region, sex, age)] * monthly[(sex, age)]
                                       for sex in ("female", "male") for age in ages)
        women = sum(pop[(region, "female", age)] * fertility[age] for age in ages)
        net = (int(c["internal_net"]) + int(c["international_net"]) + int(c["other"])) / MONTHS
        rows.append(f"{region},{r12(int(c['deaths']) / expected_deaths)},{r12(int(c['births']) / MONTHS / women)},{r12(net)}")
    (folder / "by_region.csv").write_text("\n".join(rows) + "\n", encoding="utf-8", newline="\n")
    # The population starts from the pipeline's own file.
    (out_dir / "data").mkdir(parents=True, exist_ok=True)
    if (out_dir / "data").resolve() != data_dir.resolve():
        (out_dir / "data" / "population.csv").write_bytes((data_dir / "population.csv").read_bytes())
    return {"boy_share": r12(p["boy_share"])}


def invert(matrix: list[list[float]]) -> list[list[float]]:
    """Gauss-Jordan with partial pivoting; the matrices here are 15 x 15 and well conditioned."""
    n = len(matrix)
    aug = [row[:] + [1.0 if i == j else 0.0 for j in range(n)] for i, row in enumerate(matrix)]
    for c in range(n):
        pivot = max(range(c, n), key=lambda r: abs(aug[r][c]))
        aug[c], aug[pivot] = aug[pivot], aug[c]
        p = aug[c][c]
        aug[c] = [x / p for x in aug[c]]
        for r in range(n):
            if r != c and aug[r][c] != 0.0:
                f = aug[r][c]
                aug[r] = [x - f * y for x, y in zip(aug[r], aug[c])]
    return [row[n:] for row in aug]


def write_industries(out_dir: Path) -> dict[str, str]:
    """Format 1: the industries block's coefficients from the 2023 input-output tables.
    Returns the template's fills."""
    data_dir = ROOT / "models" / "uk" / "data"

    def table(name):
        return list(csv.DictReader((data_dir / name).read_text(encoding="utf-8").splitlines()))

    industries = table("industries.csv")
    names = [r["industry"] for r in industries]
    output = {r["industry"]: float(r["output"]) for r in industries}
    z = {(r["from"], r["to"]): float(r["value"]) for r in table("io_domestic.csv")}
    totals = {r["use"]: float(r["total_purchasers_prices"]) for r in table("io_final_totals.csv")}
    # A[i][j]: domestic input from industry i per pound of industry j's output; L = (I - A)^-1.
    ident = [[(1.0 if i == j else 0.0) - z[(a, b)] / output[b] for j, b in enumerate(names)] for i, a in enumerate(names)]
    leontief = invert(ident)
    folder = out_dir / "industries"
    folder.mkdir(parents=True, exist_ok=True)
    rows = ["industry,product,value"] + [f"{a},{b},{r12(leontief[i][j])}" for i, a in enumerate(names)
                                         for j, b in enumerate(names)]
    (folder / "leontief.csv").write_text("\n".join(rows) + "\n", encoding="utf-8", newline="\n")
    uses = ("households", "government", "investment", "exports")
    rows = ["product," + ",".join(uses)]
    for r in industries:
        rows.append(r["industry"] + "," + ",".join(r12(float(r[u]) / totals[u]) for u in uses))
    (folder / "shares.csv").write_text("\n".join(rows) + "\n", encoding="utf-8", newline="\n")
    rows = ["industry,gva,compensation"] + [
        f"{r['industry']},{r12(float(r['gva']) / float(r['output']))},{r12(float(r['compensation']) / float(r['output']))}"
        for r in industries]
    (folder / "ratios.csv").write_text("\n".join(rows) + "\n", encoding="utf-8", newline="\n")
    labels = {r["industry"]: r["label"] for r in industries}
    return {"industry_members": "[" + ", ".join(f'"{n}"' for n in names) + "]",
            "industry_labels": "[" + ", ".join(f'"{labels[n]}"' for n in names) + "]"}


def household_base() -> dict[str, float]:
    """The households' taxes and benefits in the base month (pence a month), from the
    standalone households model (models/uk/households/, written by tools/uk/make_rules.py)."""
    import sys
    sys.path.insert(0, str(ROOT / "oracle"))
    from polisim_oracle import Simulation, load_model
    row = Simulation(load_model(ROOT / "models" / "uk" / "households"), seed=1).step()
    return {"income_tax": row["income_tax_total"], "ni": row["employee_ni_total"] + row["employer_ni_total"],
            "benefits": row["child_benefit_total"] + row["universal_credit_total"]}


PRESETS = ("low", "central", "high")


def pick(a: dict, preset: str) -> dict:
    """The assumptions with each behavioural range ({low, central, high}) at one preset;
    the gilt yield keeps its table, which the model carries as presets."""
    out = dict(a)
    out["behaviour"] = {k: (v[preset] if isinstance(v, dict) and k != "gilt_yield" else v)
                        for k, v in a["behaviour"].items()}
    return out


def write_model(year: str, out_dir: Path, data: dict | None = None, a: dict | None = None,
                households: Path | None = None) -> SimpleNamespace:
    """Writes the UK model for a base year into `out_dir`. `households` is the folder whose
    households.csv the model uses (default models/uk/households)."""
    ranges = a if a is not None else load_assumptions()
    a = pick(ranges, "central")
    v = derive(year, data, a)
    # Stage S6.0: each preset derives its own share of income spent, so that every preset
    # reproduces the base month.
    by_preset = {p: derive(year, data, pick(ranges, p)) for p in PRESETS}
    # The people, industries and households start from 2024 data, so only a 2024 base year
    # has them.
    people = year == STOCKS_YEAR
    base = household_base() if people else None
    be = a["behaviour"]
    out = [
        f"# Generated by tools/uk/calibrate.py from models/uk/data/annual.csv ({year}) and",
        "# tools/uk/assumptions.toml. Do not edit: change the inputs and run the script again.",
        f"# Money is in pounds; monthly amounts are one twelfth of {year}.",
        "",
    ]

    def param(name, value, unit, kind="real", doc=""):
        out.append(f"[param.{name}]")
        out.append(f'type = "{kind}"')
        out.append(f'unit = "{unit}"')
        if isinstance(value, dict):
            for k, val in value.items():
                out.append(f"{k} = {val}")
        else:
            out.append(f"value = {value}")
        if doc:
            out.append(f'doc = "{doc}"')
        out.append("")

    def lever(name, label, default, unit, rng, doc, kind="money"):
        # Amounts are set in base-year prices and uprated by the trend index, so the budget
        # line they feed is larger than the setting; the label says so.
        if kind == "money":
            label += f" ({year} prices)"
        out.append(f"[lever.{name}]")
        out.append(f'label = "{label}"')
        out.append(f'group = "{"Spending" if name.endswith("_bill") or name == "benefit_per_unemployed" else "Taxes"}"')
        out.append(f'type = "{kind}"')
        out.append(f'unit = "{unit}"')
        out.append(f"default = {default}")
        if people:  # S5.4: with a parliament, raising spending or a tax rate is a move to the left
            out.append('leaning = "left"')
        out.append(f"range = [{rng[0]}, {rng[1]}]")
        out.append(f'doc = "{doc}"')
        out.append("")

    def bn(x):
        return float(x) / 1000

    # Levers: monthly amounts in base-year prices, and tax rates.
    # Stage S8.0: with the 2024 base the public pay bill and purchases are the sums of the
    # spending by function (functions.toml), each function a lever of its own.
    if not people:
        lever("public_pay_bill", "Public sector pay bill", monthly(v.public_pay), "GBP/month",
              (0, monthly(v.public_pay) * 2),
              f"Wages and salaries of public employees, in {year} prices. {year}: £%.1fbn a year." % bn(v.public_pay))
        lever("procurement_bill", "Purchases of goods and services", monthly(v.procurement), "GBP/month",
              (0, monthly(v.procurement) * 2),
              f"What the public sector buys from firms, in {year} prices. {year}: £%.1fbn a year." % bn(v.procurement))
    other_benefits = monthly(v.benefits_other) - (round(base["benefits"] / 100) if people else 0)
    lever("benefits_bill", "Pensions and other benefits", other_benefits, "GBP/month", (0, other_benefits * 2),
          f"Social benefits that do not depend on unemployment, mostly the state pension, in {year} prices"
          + (" (Child Benefit and Universal Credit come from the households)." if people else "."))
    bpu = pounds_and_pence(v.benefit_per_unemployed)
    lever("benefit_per_unemployed", "Benefit per unemployed person", bpu, "GBP/month/person",
          (0, pounds_and_pence(v.benefit_per_unemployed * 2000 / 450)),
          f"Paid each month for each unemployed person, in {year} prices.")
    lever("public_investment_bill", "Public investment", monthly(v.public_investment), "GBP/month",
          (0, monthly(v.public_investment) * 3),
          f"Gross public investment: roads, buildings, equipment, in {year} prices. {year}: £%.1fbn a year."
          % bn(v.public_investment))
    lever("subsidies_bill", "Subsidies", monthly(v.subsidies), "GBP/month", (0, monthly(v.subsidies) * 3),
          f"Subsidies to producers, in {year} prices.")
    lever("transfers_abroad_bill", "Aid and other transfers", monthly(v.other_current), "GBP/month",
          (0, monthly(v.other_current) * 3),
          f"Other current spending, including aid and payments abroad, in {year} prices.")
    if not people:  # with households, the real rates and thresholds replace these
        lever("income_tax_rate", "Income tax, average rate", r12(v.income_tax_rate), "1", (0, 0.6),
              f"Income tax and capital gains tax as a share of household income before tax. {year}: %.1f%%."
              % (v.income_tax_rate * 100), kind="real")
        lever("nics_rate", "National Insurance, average rate", r12(v.nics_rate), "1", (0, 0.4),
              f"Employee and employer National Insurance as a share of pay. {year}: %.1f%%." % (v.nics_rate * 100),
              kind="real")
    lever("vat_rate", "VAT standard rate", r12(v.vat_rate), "1", (0, 0.5),
          "The standard rate. About %.0f%% of household spending is taxed at it." % (v.vat_base_share * 100), kind="real")
    lever("corporation_tax_rate", "Corporation tax main rate", r12(v.ct_rate), "1", (0, 0.5),
          "Main rate of corporation tax on company profits.", kind="real")
    lever("council_tax_bill", "Council tax", monthly(v.council), "GBP/month", (0, monthly(v.council) * 3),
          f"Total council tax, in {year} prices. {year}: £%.1fbn a year." % bn(v.council))

    pd = v.private_demand
    if people:
        # Income tax: the households' own, plus tax on the economy's other income (savings,
        # dividends, property, the self-employed the records miss) at the rate that makes the
        # base month one twelfth of 2024. National Insurance: the households', scaled likewise.
        param("other_income_tax_rate", r12((v.income_tax / MONTHS * 1e8 - base["income_tax"]) / (v.other_income / MONTHS * 1e8)), "1",
              doc="Income tax on other income, as a share of it")
        param("ni_scale", r12(v.nics / MONTHS * 1e8 / base["ni"]), "1",
              doc="Published National Insurance against the households' contributions in the base month")
    param("public_pay_per_worker", money(v.pay_per_worker / MONTHS), "GBP/month/person", "money",
          f"Average pay per public employee, {year}, a month")
    param("vat_base_share", r12(v.vat_base_share), "1", doc="Share of household spending taxed at the standard VAT rate")
    param("profit_tax_base_share", r12(v.ct_base_share), "1", doc="Taxable profits as a share of operating profit")
    param("production_tax_rate", r12(v.production_taxes / pd), "1", doc="Other taxes on production as a share of sales")
    param("other_receipts_share", r12(v.other_receipts / pd), "1", doc="Other public sector receipts as a share of sales")
    param("other_income_share", r12(v.other_income / pd), "1",
          doc="Self-employment, rent, dividends and other income paid to households, as a share of sales")
    param("pension_transfer_share", r12(v.pension_transfers / pd), "1",
          doc="Pension entitlements and capital transfers to households, as a share of sales")
    param("investment_share", r12(v.business_investment / pd), "1", doc="Business investment as a share of last month's sales")
    param("import_share", r12(v.imports / pd), "1", doc="Imports as a share of sales")
    param("wage_share", r12(v.private_pay / pd), "1", doc="Private pay bill as a share of last month's sales")
    param("dwellings_share", r12(v.dwellings / v.disposable_income), "1",
          doc="Household investment in dwellings as a share of disposable income")
    param("gdp_adjustment_share", r12(v.gdp_adjustment_share), "1",
          doc="Inventories, valuables and the gap between the model's and the published GDP, as a share of sales")
    param("spend_out_of_income", {p: r12(by_preset[p].income_share) for p in PRESETS}, "1",
          doc="Share of disposable income households spend each month")
    param("spend_out_of_savings", {p: r12(by_preset[p].wealth_share) for p in PRESETS}, "1/month",
          doc="Share of money holdings households spend each month")
    param("bank_payout_ratio", r12(v.payout_ratio), "1", doc="Share of gilt interest financial corporations pass on to households")
    param("exports_base", monthly(v.exports), "GBP/month", "money", "Exports in the first month")
    param("gilts_abroad_share", r12(v.abroad), "1", doc="Share of new gilts bought abroad")

    def ranged(name, convert=lambda x: x):
        """A behavioural value, or its presets when the assumptions give a range."""
        raw = ranges["behaviour"][name]
        if isinstance(raw, dict):
            return {p: r12(convert(raw[p])) for p in PRESETS}
        return r12(convert(raw))
    param("hiring_speed", ranged("hiring_speed"), "1", doc="Share of the employment gap firms close each month")
    param("labour_force_growth", ranged("labour_force_growth_annual", growth), "1", doc="Monthly growth of the labour force")
    param("productivity_growth", ranged("productivity_growth_annual", growth), "1", doc="Monthly growth of output per worker")
    param("world_growth", ranged("world_demand_growth_annual", growth), "1", doc="Monthly growth of world demand for exports, nominal")
    param("inflation_target", r12(growth(be["inflation_target_annual"])), "1",
          doc="Monthly inflation at the natural rate of unemployment")
    param("natural_unemployment", ranged("natural_unemployment"), "1", doc="Unemployment rate at which inflation is on target")
    param("phillips_slope", ranged("phillips_slope", lambda x: x / MONTHS), "1",
          doc="Monthly inflation added per point of unemployment below the natural rate")
    param("wage_curve", ranged("wage_curve", lambda x: x / MONTHS), "1",
          doc="Monthly growth of pay beyond prices and productivity per point of unemployment below the natural rate")
    param("gilt_yield", {k: r12(val) for k, val in be["gilt_yield"].items()}, "1", doc="Annual interest rate on newly issued gilts")
    param("maturity_months", r12(be["average_maturity_years"] * MONTHS), "1", doc="Average maturity of gilts, in months")
    param("interest_months", "12.0", "month", doc="Months over which an annual interest rate accrues")
    param("cash_target_months", r12(v.stocks["firm_deposits"] / (pd / MONTHS)), "month",
          doc=f"Firms' usual cash holdings, in months of sales (their {year} ratio)")
    param("loan_adjustment", ranged("loan_adjustment"), "1",
          doc="Share of firms' cash shortfall (or surplus) met by new borrowing (or repayment) each month")
    param("payout_sensitivity", ranged("payout_sensitivity"), "1",
          doc="How strongly firms' payouts respond to cash above or below its usual level")

    out.append(f"# Opening values (end of {year}), filled into model.toml and economy.toml")
    s = v.stocks
    opening = {
        "household_deposits": money(s["household_deposits"]), "firm_deposits": money(s["firm_deposits"]),
        "rest_of_world_deposits": money(s["rest_of_world_deposits"]), "government_deposits": money(s["government_deposits"]),
        "gilts_banks": money(v.debt * (1 - v.abroad)), "gilts_abroad": money(v.debt * v.abroad),
        "firm_loans": money(s["firm_bank_loans"]),
        "private_employment": r12(v.private_employment), "labour_force": r12(v.labour_force),
        # A real-valued amount of money is held in minor units (pence), like every money value.
        "private_pay_per_worker": r12(v.private_pay / v.private_employment * 1_000_000 / MONTHS * 100),
        "effective_rate": r12(v.rate), "private_demand": monthly(pd),
        "unemployment_rate": r12(v.unemployed / v.labour_force),
    }
    for k, val in opening.items():
        out.append(f"# opening.{k} = {val}")
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "calibration.toml").write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
    detail = (("population.toml", "industries.toml", "households.toml", "politics.toml", "trade.toml",
               "functions.toml", "emissions.toml", "nhs.toml", "situations.toml", "dilemmas.toml") if people else ())
    files = ["calibration.toml", "economy.toml", *detail]
    fills = {**write_population(out_dir, a), **write_industries(out_dir)} if people else {}
    if people:
        sys_path_tools = str(HERE)
        import sys
        if sys_path_tools not in sys.path:
            sys.path.insert(0, sys_path_tools)
        import jobs
        # Stage S6.4: jobs by industry, at their 2024 numbers in the base month: per person in
        # work as the model counts them there (public employment from the rounded pay bill).
        in_work = float(r12(v.private_employment)) + monthly(v.public_pay) / money(v.pay_per_worker / MONTHS)
        fills.update(jobs.write(out_dir, in_work))
        import make_rules
        source = (households or ROOT / "models" / "uk" / "households") / "households.csv"
        alignment = make_rules.write_alignment(out_dir / "households",
                                               float(v.private_employment + v.public_employment), source)
        (out_dir / "households.toml").write_text(
            make_rules.build(True, opening["private_pay_per_worker"], alignment)[1], encoding="utf-8", newline="\n")
        if (out_dir / "households" / "households.csv").resolve() != source.resolve():
            (out_dir / "households" / "households.csv").write_bytes(source.read_bytes())
        import voters
        politics, fit = voters.write(out_dir, source)
        if fit > 1e-9:
            raise SystemExit(f"the voters' intercepts do not reproduce the 2024 election: error {fit}")
        (out_dir / "politics.toml").write_text(politics, encoding="utf-8", newline="\n")
        import trade
        (out_dir / "trade.toml").write_text(trade.write(out_dir), encoding="utf-8", newline="\n")
        import functions
        with open(out_dir / "industries" / "shares.csv", newline="", encoding="utf-8") as handle:
            government = {r["product"]: float(r["government"]) for r in csv.DictReader(handle)}
        (out_dir / "functions.toml").write_text(
            functions.write(out_dir, monthly(v.public_pay), monthly(v.procurement), government),
            encoding="utf-8", newline="\n")
        import emissions
        (out_dir / "emissions.toml").write_text(emissions.write(out_dir), encoding="utf-8", newline="\n")
        import nhs
        (out_dir / "nhs.toml").write_text(nhs.write(), encoding="utf-8", newline="\n")
    fills["income_tax_expr"] = ("round(income_tax_total + other_income_tax_rate * other_income)" if people
                                else "round(income_tax_rate * (wages + public_pay + benefits + other_income))")
    fills["nics_expr"] = ("round(ni_scale * (employee_ni_total + employer_ni_total))" if people
                          else "round(nics_rate * (wages + public_pay))")
    fills["benefits_expr"] = ("round((benefits_bill + benefit_per_unemployed * unemployed) * trend_index) + child_benefit_total + universal_credit_total"
                              if people else "round((benefits_bill + benefit_per_unemployed * unemployed) * trend_index)")
    # Stage S6.3: with the 2024 base, trade is by partner (trade.toml).
    fills["exports_expr"] = ("round(sum(exports_by_partner, partner))" if people
                             else "round(exports_base * world_index * export_demand)")
    fills["imports_expr"] = ("round(sum(imports_by_partner, partner))" if people
                             else "round(import_share * import_propensity * private_demand)")
    # Customs duties (trade.toml) are public receipts too.
    fills["customs_receipts"] = " + customs_duties + carbon_tax_firms + carbon_tax_households" if people else ""
    for name in ("model.toml", "economy.toml",
                 *(d for d in detail if d not in ("households.toml", "politics.toml", "trade.toml", "functions.toml",
                                                  "emissions.toml", "nhs.toml"))):
        text = (HERE / "template" / name).read_text(encoding="utf-8")
        for k, val in opening.items():
            text = text.replace("{{opening.%s}}" % k, str(val))
        for k, val in fills.items():
            text = text.replace("{{%s}}" % k, str(val))
        text = text.replace("{{files}}", "[" + ", ".join(f'"{f}"' for f in files) + "]")
        text = text.replace("{{base_year}}", year)
        if "{{" in text.replace("{{double braces}}", ""):
            raise SystemExit(f"{name}: a placeholder was not filled")
        (out_dir / name).write_text(text, encoding="utf-8", newline="\n")
    return v


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--base-year", default=DEFAULT_BASE)
    parser.add_argument("--out", type=Path, default=ROOT / "models" / "uk")
    parser.add_argument("--households", type=Path, help="folder of households.csv (default models/uk/households)")
    args = parser.parse_args()
    v = write_model(args.base_year, args.out, households=args.households)
    print(f"{v.year} accounts the first month reproduces (x12), £bn a year:")
    for label, value in [("Household consumption", v.consumption), ("Disposable income", v.disposable_income),
                         ("Public current receipts", v.receipts), ("Public net borrowing", v.borrowing),
                         ("GDP", v.gdp), ("Exports", v.exports), ("Imports", v.imports),
                         ("Business investment (estimate)", v.business_investment)]:
        print(f"  {label:32} {float(value) / 1000:9.1f}")
    print(f"  effective interest rate on debt {float(v.rate) * 100:.2f}%   "
          f"unemployment {float(v.unemployed / v.labour_force) * 100:.2f}%")
    print(f"  income share spent {float(v.income_share):.4f}   payout ratio {float(v.payout_ratio):.4f}")


if __name__ == "__main__":
    main()
