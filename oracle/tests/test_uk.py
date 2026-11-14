"""The UK national model, version 0 (docs/S3-PLAN.md, milestone S3.2).

The model is calibrated so that its first month is one twelfth of the 2024 national
accounts and public finances. These tests hold it to that, check that money, gilts and
loans balance on every step, and check that thirty years of unchanged policy stay inside
broad, plausible ranges. They are not a validation against history: that is the hindcast
(S3.4).
"""

from __future__ import annotations

import csv
import functools
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from polisim_oracle import Simulation, load_model  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
UK = ROOT / "models" / "uk"
SEED = 2025
PENCE_PER_MILLION = 100_000_000  # £1 million in pence
MONTHS = 12


@functools.lru_cache(maxsize=None)
def model():
    return load_model(UK)


@functools.lru_cache(maxsize=None)
def run(steps: int = 360, preset: str = "central"):
    return Simulation(model(), seed=SEED, preset=preset).run(steps)


@functools.lru_cache(maxsize=None)
def published(year: str = "2024") -> dict[str, float]:
    with open(UK / "data" / "annual.csv", newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if row["period"] == year:
                return {k: float(v) for k, v in row.items() if k != "period" and v != ""}
    raise KeyError(year)


def annualised(row, *names) -> float:
    """Twelve times a month's flows, in £ million a year."""
    return sum(row[n] for n in names) * MONTHS / PENCE_PER_MILLION


class FirstMonth(unittest.TestCase):
    """Month one is January 2025, one month on from the 2024 base: prices have risen by one
    month of inflation (about 0.17%), so flows are matched to within half a percent."""

    def assertClose(self, got, want, tolerance=0.005, what=""):
        self.assertLess(abs(got / want - 1), tolerance, f"{what}: model {got:,.0f}, published {want:,.0f}")

    def test_national_accounts(self):
        first, p = run()[0], published()
        self.assertClose(annualised(first, "gdp"), p["gdp"], what="GDP")
        self.assertClose(annualised(first, "consumption"), p["household_consumption"] + p["npish_consumption"],
                         what="consumption")
        self.assertClose(annualised(first, "wages", "public_pay"), p["compensation_of_employees"],
                         what="compensation of employees")
        self.assertClose(annualised(first, "disposable_income"), p["household_disposable_income"],
                         what="disposable income")
        self.assertClose(annualised(first, "exports"), p["exports"], what="exports")
        self.assertClose(annualised(first, "imports"), p["imports"], what="imports")

    def test_public_finances(self):
        first, p = run()[0], published()
        self.assertClose(annualised(first, "public_receipts"), p["ps_current_receipts"], what="receipts")
        self.assertClose(annualised(first, "income_tax"), p["income_tax"], what="income tax")
        self.assertClose(annualised(first, "national_insurance"), p["social_contributions"], what="NICs")
        self.assertClose(annualised(first, "vat"), p["vat"], what="VAT")
        self.assertClose(annualised(first, "corporation_tax"), p["corporation_tax"], what="corporation tax")
        self.assertClose(annualised(first, "budget_balance"), p["ps_net_borrowing"], what="net borrowing")
        # Debt at the end of the month, less that month's borrowing, is the 2024 figure.
        opening = (first["public_debt"] - first["borrowing"]) / PENCE_PER_MILLION
        self.assertClose(opening, p["ps_net_debt"] * 1000, tolerance=1e-9, what="net debt")

    def test_labour_market(self):
        first, p = run()[0], published()
        self.assertAlmostEqual(first["unemployment_rate"], p["unemployment_rate"] / 100, delta=0.0005)
        self.assertAlmostEqual(first["employment"] / 1000, p["employment"], delta=p["employment"] * 0.002)


class SectorBalances(unittest.TestCase):
    """Net lending is the change in what a sector holds. Households and financial
    corporations reproduce 2024. The model's government is the public sector, measured as
    public sector net borrowing, which was £25.7bn less than general government's net
    borrowing in the sector accounts; firms carry that difference, so they are left out."""

    def net_lending(self):
        sim = Simulation(model(), seed=SEED)
        before = {name: sim.rt.S[name] for name in model().accounts.values()}
        row = sim.step()
        totals: dict[str, float] = {}
        for (sector, _), name in model().accounts.items():
            totals[sector] = totals.get(sector, 0) + (row[name] - before[name]) * MONTHS / PENCE_PER_MILLION
        return totals

    def test_first_month_net_lending(self):
        lending, p = self.net_lending(), published()
        self.assertAlmostEqual(lending["households"], p["net_lending_households"], delta=50)
        self.assertAlmostEqual(lending["banks"], p["net_lending_financial_corporations"], delta=50)
        self.assertAlmostEqual(lending["government"], p["ps_net_borrowing"], delta=50)
        abroad = p["net_lending_rest_of_world"]
        self.assertAlmostEqual(lending["rest_of_world"], abroad, delta=0.03 * abs(abroad))
        self.assertAlmostEqual(sum(lending.values()), 0, delta=1e-6)


class Accounting(unittest.TestCase):
    def test_every_instrument_nets_to_zero_on_every_step(self):
        for row in run():
            money = sum(row[k] for k in ("household_money", "firm_money", "bank_money", "government_money",
                                         "foreign_money"))
            self.assertEqual(money, 0, f"money at step {row['step']}")
            self.assertEqual(row["gilts_issued"] + row["bank_gilts"] + row["foreign_gilts"], 0)
            self.assertEqual(row["firm_loans"] + row["bank_loans"], 0)

    def test_debt_rises_by_exactly_the_deficit(self):
        rows = run()
        for before, after in zip(rows, rows[1:]):
            self.assertEqual(after["public_debt"] - before["public_debt"], -after["budget_balance"],
                             f"step {after['step']}")

    def test_borrowing_is_the_deficit_and_repayment_the_surplus(self):
        for row in run():
            self.assertEqual(row["borrowing"] - row["repayment"], -row["budget_balance"])
            self.assertGreaterEqual(min(row["borrowing"], row["repayment"]), 0)


class UnchangedPolicy(unittest.TestCase):
    """Thirty years with 2024 policy, uprated with prices and earnings. Ranges are wide on
    purpose: they catch a model that breaks, not one that is slightly off."""

    def test_unemployment_stays_between_three_and_seven_percent(self):
        rates = [row["unemployment_rate"] for row in run()]
        self.assertGreater(min(rates), 0.03)
        self.assertLess(max(rates), 0.07)

    def test_inflation_stays_near_the_target(self):
        rates = [row["inflation_annual"] for row in run()[12:]]
        self.assertGreater(min(rates), 0.0)
        self.assertLess(max(rates), 0.04)

    def test_real_growth_is_between_one_and_two_and_a_half_percent(self):
        rows = run()
        first = sum(r["real_gdp"] for r in rows[:12])
        last = sum(r["real_gdp"] for r in rows[-12:])
        growth = (last / first) ** (1 / 29) - 1
        self.assertGreater(growth, 0.01)
        self.assertLess(growth, 0.025)

    def test_no_sector_runs_out_of_money(self):
        for row in run():
            for k in ("household_money", "firm_money", "foreign_money"):
                self.assertGreater(row[k], 0, f"{k} at step {row['step']}")

    def test_debt_stays_below_twice_output(self):
        # Known weakness of version 0: with no fiscal rule the deficit drifts up and debt
        # rises from 97% to about 150% of GDP in thirty years. See docs/S3-PLAN.md.
        self.assertLess(max(row["debt_to_gdp"] for row in run()), 2.0)

    def test_the_presets_all_run(self):
        for preset in ("low", "central", "high"):
            rows = run(120, preset)
            self.assertEqual(len(rows), 120)


class Population(unittest.TestCase):
    """The people block (S3.6): ONS's mid-2024 population by region, sex and age, moved on
    month by month."""

    @staticmethod
    def table(name):
        with open(UK / "data" / name, newline="", encoding="utf-8") as handle:
            return list(csv.DictReader(handle))

    def test_the_first_month_starts_from_the_published_population(self):
        sim = Simulation(model(), seed=SEED)
        cells = self.table("population.csv")
        regions = model().dims["region"].members
        sexes = model().dims["sex"].members
        for row in cells[:: 17]:
            flat = (regions.index(row["region"]) * 2 + sexes.index(row["sex"])) * 91 + int(row["age"])
            self.assertEqual(sim.rt.C["population"][flat], float(row["people"]))
        self.assertEqual(run()[0]["population_total"], float(sum(int(r["people"]) for r in cells)))
        self.assertEqual(run()[0]["population_total"], 69_281_437)

    def test_the_first_months_births_and_deaths_are_a_twelfth_of_the_published_year(self):
        change = self.table("population_change.csv")
        first = run()[0]
        self.assertAlmostEqual(first["births_total"] * 12, sum(int(c["births"]) for c in change), delta=1)
        self.assertAlmostEqual(first["deaths_total"] * 12, sum(int(c["deaths"]) for c in change), delta=1)

    def test_a_year_on_the_population_has_grown_by_about_the_published_change(self):
        change = self.table("population_change.csv")
        published = sum(int(c["population_2024"]) - int(c["population_2023"]) for c in change)
        grown = run()[12]["population_total"] - run()[0]["population_total"]
        self.assertLess(abs(grown / published - 1), 0.05)

    def test_thirty_years_stay_plausible(self):
        rows = run()
        self.assertTrue(70e6 < rows[-1]["population_total"] < 95e6)
        share_old = rows[-1]["pension_age_population"] / rows[-1]["population_total"]
        self.assertTrue(0.17 < share_old < 0.35)


class Industries(unittest.TestCase):
    """The industries block (S3.6): spending turned into output by industry through the
    2023 input-output tables."""

    @staticmethod
    def table(name, folder=UK / "data"):
        with open(folder / name, newline="", encoding="utf-8") as handle:
            return list(csv.DictReader(handle))

    def test_the_leontief_inverse_turns_the_tables_final_demand_into_their_output(self):
        industries = self.table("industries.csv")
        names = [r["industry"] for r in industries]
        final = {r["industry"]: sum(float(r[k]) for k in ("households", "government", "investment", "exports"))
                 for r in industries}
        inverse = {(r["industry"], r["product"]): float(r["value"]) for r in self.table("leontief.csv", UK / "industries")}
        for r in industries:
            made = sum(inverse[(r["industry"], p)] * final[p] for p in names)
            self.assertAlmostEqual(made / float(r["output"]), 1.0, places=6, msg=r["industry"])

    def test_industries_add_up_to_national_output_in_the_first_month(self):
        first, p23, p24 = run()[0], published("2023"), published("2024")
        gva_2024 = 2_497_390 / p23["gdp"] * p24["gdp"]  # the tables' value added, scaled to 2024
        self.assertLess(abs(first["gva_by_industries"] * 12 / PENCE_PER_MILLION / gva_2024 - 1), 0.02)

    def test_each_industry_is_near_the_tables_scaled_to_2024(self):
        sim = Simulation(model(), seed=SEED)
        sim.step()
        scale = published("2024")["gdp"] / published("2023")["gdp"]
        outputs = dict(zip(model().dims["industry"].members, sim.rt.C["industry_output"]))
        for r in self.table("industries.csv"):
            got = outputs[r["industry"]] * 12 / PENCE_PER_MILLION
            self.assertLess(abs(got / (float(r["output"]) * scale) - 1), 0.05, r["industry"])

    def test_a_cut_in_public_spending_falls_mostly_on_public_services(self):
        base = Simulation(model(), seed=SEED)
        cut = Simulation(model(), seed=SEED, levers={"procurement_bill": 20_000_000_000})
        base.step()
        cut.step()
        names = model().dims["industry"].members
        fall = {n: b - c for n, b, c in zip(names, base.rt.C["industry_output"], cut.rt.C["industry_output"])}
        services = fall["public_administration"] + fall["education"] + fall["health"]
        self.assertGreater(services, 0.5 * sum(fall.values()))


class Reproducibility(unittest.TestCase):
    def test_matches_the_recorded_hashes(self):
        # Recorded with:
        # python -m polisim_oracle run ../models/uk/scenarios/2025.toml --steps 120
        #     --columns step,hash --out ../models/uk/golden/2025.hashes.csv
        with open(UK / "golden" / "2025.hashes.csv", newline="", encoding="utf-8") as handle:
            golden = [row["hash"] for row in csv.DictReader(handle)]
        self.assertEqual(len(golden), 120)
        self.assertEqual([row["hash"] for row in run()[:120]], golden)


if __name__ == "__main__":
    unittest.main()
