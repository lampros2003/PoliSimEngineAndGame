"""Derive the UK model's parameters and lever settings from the 2024 accounts.

    python tools/uk/calibrate.py

Reads models/uk/data/annual.csv and tools/uk/assumptions.toml, writes
models/uk/calibration.toml, and prints the base-year accounts the model reproduces. Every
number written is either a published 2024 figure (as one twelfth, for a month), an
assumption, or derived from those so that the first month of a run equals one twelfth of
2024. The derivations are spelled out next to each value in the output file.
"""

from __future__ import annotations

import csv
import tomllib
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE_YEAR = "2024"
MONTHS = 12


def money(pounds_million: Fraction | float | int) -> int:
    """£ million a year or a stock -> whole pounds, rounded half to even."""
    return round(Fraction(pounds_million) * 1_000_000)


def monthly(annual_million: Fraction | int) -> int:
    return money(Fraction(annual_million) / MONTHS)


def main() -> None:
    rows = {r["period"]: r for r in csv.DictReader((ROOT / "models/uk/data/annual.csv").read_text().splitlines())}
    d = {k: Fraction(v) for k, v in rows[BASE_YEAR].items() if k != "period" and v != ""}
    a = tomllib.loads((ROOT / "tools/uk/assumptions.toml").read_text())
    st, be = a["stocks"], a["behaviour"]

    # ---- published 2024 figures, £ million a year
    consumption = d["household_consumption"] + d["npish_consumption"]
    public_pay = d["cg_staff_costs"] + d["lg_staff_costs"]
    procurement = d["cg_procurement"] + d["lg_procurement"]
    benefits = d["ps_social_benefits"]
    interest = d["ps_interest"]
    subsidies = d["ps_subsidies"]
    other_current = d["ps_current_expenditure"] - (public_pay + procurement + benefits + interest + subsidies)
    public_investment = d["ps_depreciation"] - d["ps_net_investment"]  # gross: depreciation plus net
    income_tax, nics, vat, corp_tax = d["income_tax"], d["social_contributions"], d["vat"], d["corporation_tax"]
    council = d["council_tax"]
    production_taxes = d["taxes_on_production"] - vat
    receipts = d["ps_current_receipts"]
    other_receipts = receipts - (income_tax + nics + vat + corp_tax + production_taxes + council)
    debt = d["ps_net_debt"] * 1000  # £ billion -> £ million
    dwellings_and_more = None
    exports, imports = d["exports"], d["imports"]
    compensation = d["compensation_of_employees"]
    private_pay = compensation - public_pay
    disposable_income = d["household_disposable_income"]
    # Business investment: whole-economy investment less public investment and an estimate
    # of households' dwellings (taken as 21% of investment, the share of new dwellings in
    # 2024's total; refined when the dwellings series joins the pipeline).
    dwellings = d["investment"] * Fraction(21, 100)
    business_investment = d["investment"] - public_investment - dwellings
    private_demand = consumption + dwellings + procurement + public_investment + business_investment + exports

    # ---- employment
    employed = d["employment"] * 1000
    unemployed = d["unemployed"] * 1000
    labour_force = employed + unemployed
    pay_per_worker = compensation / employed  # £ million a year per person
    public_employment = public_pay / pay_per_worker
    private_employment = employed - public_employment

    # ---- money and interest
    rate = interest / debt
    abroad = Fraction(str(st["gilts_held_abroad"]))
    interest_banks = interest * (1 - abroad)
    payout_ratio = (interest_banks - d["net_lending_financial_corporations"]) / interest_banks

    # ---- households: other income makes disposable income match; transfers outside
    # disposable income (pension adjustment, capital transfers) make net lending match.
    benefit_unemployed = Fraction(be["benefit_per_unemployed"]) * MONTHS / 1_000_000  # £m a year per person
    benefits_other = benefits - benefit_unemployed * unemployed
    bank_payout = interest_banks * payout_ratio
    other_income = disposable_income - (compensation + benefits + bank_payout - income_tax - nics - council)
    income_tax_rate = income_tax / (compensation + benefits + other_income)
    nics_rate = nics / compensation
    pension_transfers = d["net_lending_households"] - disposable_income + consumption + dwellings
    wealth_share = Fraction(str(be["spend_out_of_savings"]))
    income_share = (consumption / MONTHS - wealth_share * st["household_deposits"]) / (disposable_income / MONTHS)

    # ---- firms and the government's other levies
    vat_rate = Fraction(1, 5)
    effective = vat / consumption
    vat_base_share = effective / (1 - effective) / vat_rate
    profit = private_demand - imports - private_pay - vat - production_taxes - other_income
    ct_rate = Fraction(1, 4)
    ct_base_share = corp_tax / (ct_rate * profit)
    gdp_model = consumption + dwellings + business_investment + public_investment + procurement + public_pay + exports - imports
    gdp_adjustment_share = (d["gdp"] - gdp_model) / private_demand

    def growth(annual: float) -> float:
        return round((1 + annual) ** (1 / 12) - 1, 12)

    out = [
        "# Generated by tools/uk/calibrate.py from models/uk/data/annual.csv (2024) and",
        "# tools/uk/assumptions.toml. Do not edit: change the inputs and run the script again.",
        "# Money is in pounds; monthly amounts are one twelfth of 2024.",
        "",
    ]

    def param(name, value, unit, kind="real", doc=""):
        out.append(f"[param.{name}]")
        out.append(f'type = "{kind}"')
        out.append(f'unit = "{unit}"')
        if isinstance(value, dict):
            for k, v in value.items():
                out.append(f"{k} = {v}")
        else:
            out.append(f"value = {value}")
        if doc:
            out.append(f'doc = "{doc}"')
        out.append("")

    def lever(name, label, default, unit, rng, doc, kind="money"):
        # Amounts are set in 2024 prices and uprated by the trend index, so the budget
        # line they feed is larger than the setting; the label says so.
        if kind == "money":
            label += " (2024 prices)"
        out.append(f"[lever.{name}]")
        out.append(f'label = "{label}"')
        out.append(f'type = "{kind}"')
        out.append(f'unit = "{unit}"')
        out.append(f"default = {default}")
        out.append(f"range = [{rng[0]}, {rng[1]}]")
        out.append(f'doc = "{doc}"')
        out.append("")

    def r12(x):
        return repr(round(float(x), 12))

    # Levers: monthly amounts in 2024 prices, and tax rates.
    lever("public_pay_bill", "Public sector pay bill", monthly(public_pay), "GBP/month", (0, monthly(public_pay) * 2),
          "Wages and salaries of public employees, in 2024 prices. 2024: £%.1fbn a year." % (public_pay / 1000))
    lever("procurement_bill", "Purchases of goods and services", monthly(procurement), "GBP/month", (0, monthly(procurement) * 2),
          "What the public sector buys from firms, in 2024 prices. 2024: £%.1fbn a year." % (procurement / 1000))
    lever("benefits_bill", "Pensions and other benefits", monthly(benefits_other), "GBP/month", (0, monthly(benefits_other) * 2),
          "Social benefits that do not depend on unemployment, mostly the state pension, in 2024 prices.")
    lever("benefit_per_unemployed", "Benefit per unemployed person", be["benefit_per_unemployed"], "GBP/month/person", (0, 2000),
          "Paid each month for each unemployed person, in 2024 prices.")
    lever("public_investment_bill", "Public investment", monthly(public_investment), "GBP/month", (0, monthly(public_investment) * 3),
          "Gross public investment: roads, buildings, equipment, in 2024 prices. 2024: £%.1fbn a year." % (public_investment / 1000))
    lever("subsidies_bill", "Subsidies", monthly(subsidies), "GBP/month", (0, monthly(subsidies) * 3), "Subsidies to producers, in 2024 prices.")
    lever("transfers_abroad_bill", "Aid and other transfers", monthly(other_current), "GBP/month", (0, monthly(other_current) * 3),
          "Other current spending, including aid and payments abroad, in 2024 prices.")
    lever("income_tax_rate", "Income tax, average rate", r12(income_tax_rate), "1", (0, 0.6),
          "Income tax and capital gains tax as a share of household income before tax. 2024: %.1f%%." % (income_tax_rate * 100), kind="real")
    lever("nics_rate", "National Insurance, average rate", r12(nics_rate), "1", (0, 0.4),
          "Employee and employer National Insurance as a share of pay. 2024: %.1f%%." % (nics_rate * 100), kind="real")
    lever("vat_rate", "VAT standard rate", "0.2", "1", (0, 0.5),
          "The standard rate. About %.0f%% of household spending is taxed at it." % (vat_base_share * 100), kind="real")
    lever("corporation_tax_rate", "Corporation tax main rate", "0.25", "1", (0, 0.5), "Main rate of corporation tax on company profits.", kind="real")
    lever("council_tax_bill", "Council tax", monthly(council), "GBP/month", (0, monthly(council) * 3),
          "Total council tax, in 2024 prices. 2024: £%.1fbn a year." % (council / 1000))

    param("public_pay_per_worker", money(pay_per_worker / MONTHS), "GBP/month/person", "money", "Average pay per public employee, 2024, a month")
    param("vat_base_share", r12(vat_base_share), "1", doc="Share of household spending taxed at the standard VAT rate")
    param("profit_tax_base_share", r12(ct_base_share), "1", doc="Taxable profits as a share of operating profit")
    param("production_tax_rate", r12(production_taxes / private_demand), "1", doc="Other taxes on production as a share of sales")
    param("other_receipts_share", r12(other_receipts / private_demand), "1", doc="Other public sector receipts as a share of sales")
    param("other_income_share", r12(other_income / private_demand), "1", doc="Self-employment, rent, dividends and other income paid to households, as a share of sales")
    param("pension_transfer_share", r12(pension_transfers / private_demand), "1", doc="Pension entitlements and capital transfers to households, as a share of sales")
    param("investment_share", r12(business_investment / private_demand), "1", doc="Business investment as a share of last month's sales")
    param("import_share", r12(imports / private_demand), "1", doc="Imports as a share of sales")
    param("wage_share", r12(private_pay / private_demand), "1", doc="Private pay bill as a share of last month's sales")
    param("dwellings_share", r12(dwellings / disposable_income), "1", doc="Household investment in dwellings as a share of disposable income")
    param("gdp_adjustment_share", r12(gdp_adjustment_share), "1", doc="Inventories, valuables and the gap between the model's and the published GDP, as a share of sales")
    param("spend_out_of_income", {"low": r12(income_share - Fraction(3, 100)), "central": r12(income_share), "high": r12(income_share + Fraction(3, 100))}, "1",
          doc="Share of disposable income households spend each month")
    param("spend_out_of_savings", r12(wealth_share), "1/month", doc="Share of money holdings households spend each month")
    param("bank_payout_ratio", r12(payout_ratio), "1", doc="Share of gilt interest financial corporations pass on to households")
    param("exports_base", monthly(exports), "GBP/month", "money", "Exports in the first month")
    param("gilts_abroad_share", r12(abroad), "1", doc="Share of new gilts bought abroad")
    param("hiring_speed", r12(be["hiring_speed"]), "1", doc="Share of the employment gap firms close each month")
    param("labour_force_growth", r12(growth(be["labour_force_growth_annual"])), "1", doc="Monthly growth of the labour force")
    param("productivity_growth", r12(growth(be["productivity_growth_annual"])), "1", doc="Monthly growth of output per worker")
    param("world_growth", r12(growth(be["world_demand_growth_annual"])), "1", doc="Monthly growth of world demand for exports, nominal")
    param("inflation_target", r12(growth(be["inflation_target_annual"])), "1", doc="Monthly inflation at the natural rate of unemployment")
    param("natural_unemployment", r12(be["natural_unemployment"]), "1", doc="Unemployment rate at which inflation is on target")
    param("phillips_slope", r12(be["phillips_slope"] / MONTHS), "1", doc="Monthly inflation added per point of unemployment below the natural rate")
    gy = be["gilt_yield"]
    param("gilt_yield", {k: r12(v) for k, v in gy.items()}, "1", doc="Annual interest rate on newly issued gilts")
    param("maturity_months", r12(be["average_maturity_years"] * MONTHS), "1", doc="Average maturity of gilts, in months")
    param("interest_months", "12.0", "month", doc="Months over which an annual interest rate accrues")
    param("cash_target_months", r12(Fraction(st["firm_deposits"]) / (private_demand / MONTHS)), "month",
          doc="Firms' usual cash holdings, in months of sales (their 2024 ratio)")
    param("loan_adjustment", r12(be["loan_adjustment"]), "1",
          doc="Share of firms' cash shortfall (or surplus) met by new borrowing (or repayment) each month")
    param("payout_sensitivity", r12(be["payout_sensitivity"]), "1",
          doc="How strongly firms' payouts respond to cash above or below its usual level")

    out.append("# Opening values (end of 2024), filled into model.toml and economy.toml")
    opening = {
        "household_deposits": money(st["household_deposits"]), "firm_deposits": money(st["firm_deposits"]),
        "rest_of_world_deposits": money(st["rest_of_world_deposits"]), "government_deposits": money(st["government_deposits"]),
        "gilts_banks": money(debt * (1 - abroad)), "gilts_abroad": money(debt * abroad),
        "firm_loans": money(st["firm_bank_loans"]),
        "private_employment": r12(private_employment), "labour_force": r12(labour_force),
        # A real-valued amount of money is held in minor units (pence), like every money value.
        "private_pay_per_worker": r12(private_pay / private_employment * 1_000_000 / MONTHS * 100),
        "effective_rate": r12(rate), "private_demand": monthly(private_demand),
        "unemployment_rate": r12(unemployed / labour_force),
    }
    for k, v in opening.items():
        out.append(f"# opening.{k} = {v}")
    (ROOT / "models/uk/calibration.toml").write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
    for name in ("model.toml", "economy.toml"):
        text = (ROOT / "tools/uk/template" / name).read_text(encoding="utf-8")
        for k, v in opening.items():
            text = text.replace("{{opening.%s}}" % k, str(v))
        if "{{" in text.replace("{{double braces}}", ""):
            raise SystemExit(f"{name}: a placeholder was not filled")
        (ROOT / "models/uk" / name).write_text(text, encoding="utf-8", newline="\n")

    print("2024 accounts the first month reproduces (x12), £bn a year:")
    for label, value in [("Household consumption", consumption), ("Disposable income", disposable_income),
                         ("Public current receipts", receipts), ("Public net borrowing", -d["ps_net_borrowing"]),
                         ("GDP", d["gdp"]), ("Exports", exports), ("Imports", imports), ("Business investment (estimate)", business_investment)]:
        print(f"  {label:32} {float(value) / 1000:9.1f}")
    print(f"  effective interest rate on debt {float(rate) * 100:.2f}%   unemployment {float(unemployed / labour_force) * 100:.2f}%")
    print(f"  income share spent {float(income_share):.4f}   payout ratio {float(payout_ratio):.4f}")
    del dwellings_and_more


if __name__ == "__main__":
    main()
