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


# With 20,000 households the oracle takes about a second a month, so these tests cover two
# years; the 30-year checks run on the engine (crates/core/tests/uk_long_run.rs), which the
# recorded hashes below hold to the oracle.
STEPS = 24


@functools.lru_cache(maxsize=None)
def run(steps: int = STEPS, preset: str = "central"):
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


class Presets(unittest.TestCase):
    def test_the_presets_all_run(self):
        for preset in ("low", "central", "high"):
            self.assertEqual(len(run(3, preset)), 3)

    def test_every_preset_reproduces_the_base_month(self):
        # Stage S6.0: the presets differ in how the economy and the voters move, not in where
        # they start: consumption, GDP, unemployment and the polls of the first month agree.
        central = run(3, "central")[0]
        for preset in ("low", "high"):
            first = run(3, preset)[0]
            for name in ("consumption", "gdp"):
                self.assertLess(abs(first[name] / central[name] - 1), 1e-6, (preset, name))
            for name in ("unemployment_rate", "government_support", "turnout"):
                self.assertAlmostEqual(first[name], central[name], places=9, msg=(preset, name))

    def test_the_presets_spread_the_outcomes(self):
        # Higher world demand, productivity and labour force growth in the high preset.
        self.assertLess(run(3, "low")[-1]["gdp"], run(3, "high")[-1]["gdp"])


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


class Households(unittest.TestCase):
    """The households and their 2024-25 rules inside the national model (milestone S4.3)."""

    def test_the_base_month_still_reproduces_2024(self):
        first, p = run()[0], published()
        self.assertAlmostEqual(first["income_tax"] * MONTHS / PENCE_PER_MILLION, p["income_tax"], delta=1)
        self.assertAlmostEqual(first["national_insurance"] * MONTHS / PENCE_PER_MILLION, p["social_contributions"], delta=1)
        self.assertAlmostEqual(first["benefits"] * MONTHS / PENCE_PER_MILLION, p["ps_social_benefits"], delta=5)

    def test_a_higher_personal_allowance_cuts_tax_and_lifts_spending(self):
        base = Simulation(model(), seed=SEED).run(2)
        cut = Simulation(model(), seed=SEED, levers={"personal_allowance": 15000}).run(2)
        self.assertLess(cut[0]["income_tax"], base[0]["income_tax"])
        self.assertGreater(cut[0]["disposable_income"], base[0]["disposable_income"])
        self.assertGreater(cut[1]["consumption"], base[1]["consumption"])

    def test_the_base_month_keeps_the_base_weights(self):
        with open(UK / "households" / "households.csv", newline="", encoding="utf-8") as handle:
            base = sum(int(r["weight"]) for r in csv.DictReader(handle))
        self.assertEqual(run()[0]["households_total"], base)

    def test_people_in_work_follow_the_economys_employment(self):
        # Stage S4.4: raked each month from the second, the households' workers are the
        # economy's employment, to within rounding of the weights.
        for row in run()[1:]:
            self.assertLess(abs(row["workers_in_households"] / row["employment"] - 1), 1e-4, row["step"])

    def test_households_grow_with_the_population(self):
        rows = run()
        households = rows[-1]["households_total"] / rows[0]["households_total"] - 1
        people = rows[-1]["population_total"] / rows[0]["population_total"] - 1
        self.assertGreater(households, 0)
        self.assertLess(abs(households - people), 0.01)

    def test_without_alignment_the_weights_stay(self):
        rows = Simulation(model(), seed=SEED, levers={"align_households": False}).run(2)
        self.assertEqual(rows[0]["households_total"], rows[1]["households_total"])

    def test_the_average_rate_levers_are_gone(self):
        names = set(model().symbols)
        self.assertNotIn("income_tax_rate", names)
        self.assertNotIn("nics_rate", names)
        self.assertIn("personal_allowance", names)


class Reproducibility(unittest.TestCase):
    def test_matches_the_recorded_hashes(self):
        # Recorded with:
        # python -m polisim_oracle run ../models/uk/scenarios/2025.toml --steps 120
        #     --columns step,hash --out ../models/uk/golden/2025.hashes.csv   (with --steps 24)
        with open(UK / "golden" / "2025.hashes.csv", newline="", encoding="utf-8") as handle:
            golden = [row["hash"] for row in csv.DictReader(handle)]
        self.assertEqual(len(golden), STEPS)
        self.assertEqual([row["hash"] for row in run()], golden)


if __name__ == "__main__":
    unittest.main()


class Jobs(unittest.TestCase):
    """Stage S6.4: jobs by industry, at their 2024 numbers in the first month
    (models/uk/data/industry_jobs.csv, from ONS JOBS02), then each industry's share of the
    jobs following its output against the others'."""

    MONTHS = 4

    @staticmethod
    def sim(**kw):
        return Simulation(model(), seed=SEED, **kw)

    def test_the_first_month_has_2024_jobs_by_industry(self):
        with open(UK / "data" / "industry_jobs.csv", newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual([r["industry"] for r in rows], model().dims["industry"].members)
        sim = self.sim()
        row = sim.step()
        for r, jobs in zip(rows, sim.column("industry_jobs")):
            self.assertAlmostEqual(jobs / (float(r["workforce_jobs"]) * 1000), 1.0, places=12, msg=r["industry"])
        self.assertAlmostEqual(row["workforce_jobs"], sum(float(r["workforce_jobs"]) * 1000 for r in rows), delta=1e-6)

    def test_the_shares_add_to_one_and_the_jobs_to_the_total(self):
        sim = self.sim()
        for _ in range(self.MONTHS):
            row = sim.step()
            self.assertAlmostEqual(sum(sim.column("industry_job_share")), 1.0, places=12)
            self.assertAlmostEqual(sum(sim.column("industry_jobs")) / row["workforce_jobs"], 1.0, places=12)
            self.assertAlmostEqual(row["workforce_jobs"] / row["employment"], model().symbols["jobs_per_worker"].spec["value"],
                                   places=12)

    def test_a_cut_in_public_spending_moves_jobs_out_of_public_services(self):
        names = model().dims["industry"].members
        public = [names.index(n) for n in ("public_administration", "education", "health")]
        cut = {1: {"procurement_bill": 20_000_000_000}}

        def public_share(**kw) -> float:
            sim = self.sim(**kw)
            for _ in range(self.MONTHS):
                sim.step()
            return sum(sim.column("industry_job_share")[i] for i in public)

        base = public_share()
        half = public_share(commands=cut) - base
        whole = public_share(commands=cut, params={"jobs_output_elasticity": 1.0}) - base
        # A quarter of procurement gone (from £27bn a month to £20bn) takes public services' share of jobs down.
        self.assertLess(half, -0.001)
        # Twice the elasticity, about twice the move.
        self.assertAlmostEqual(whole / half, 2.0, delta=0.1)

    def test_pay_per_employee_job_is_the_industries_pay_over_their_employees(self):
        sim = self.sim()
        row = sim.step()
        employees = [j * s for j, s in zip(sim.column("industry_jobs"), sim.column("employee_share"))]
        self.assertAlmostEqual(row["pay_per_employee_job"] / (sum(sim.column("industry_pay")) / sum(employees)), 1.0,
                               places=12)
        by_industry = dict(zip(model().dims["industry"].members, sim.column("industry_pay_per_employee")))
        # Finance pays most, hospitality and agriculture least, as in the tables.
        self.assertEqual(max(by_industry, key=by_industry.get), "finance")
        self.assertEqual(sorted(by_industry, key=by_industry.get)[:2], ["agriculture", "other_services"])


class Trade(unittest.TestCase):
    """Stage S6.3: trade by partner, at the 2024 shares (models/uk/data/trade_partners.csv)."""

    def test_partners_add_up_to_2024_trade(self):
        with open(UK / "data" / "trade_partners.csv", newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        exports = sum(float(r["exports"]) for r in rows)
        imports = sum(float(r["imports"]) for r in rows)
        self.assertAlmostEqual(exports / published()["exports"], 1.0, delta=0.001)
        self.assertAlmostEqual(imports / published()["imports"], 1.0, delta=0.001)
        sim = Simulation(model(), seed=SEED)
        sim.step()
        by_partner = sim.column("exports_by_partner")
        for r, value in zip(rows, by_partner):
            self.assertAlmostEqual(value / (sum(by_partner)), float(r["exports"]) / exports, places=9)

    def test_a_barrier_cuts_trade_with_that_partner_and_raises_duties(self):
        base = Simulation(model(), seed=SEED)
        base.step()
        walled = Simulation(model(), seed=SEED, levers={"trade_barrier_china": 0.2})
        row = walled.step()
        china = model().dims["partner"].members.index("china")
        # Exports to China fall by 40% (2 times the barrier); to the EU they do not change.
        exports, exports_base = walled.column("exports_by_partner"), base.column("exports_by_partner")
        self.assertAlmostEqual(exports[china] / exports_base[china], 0.6, places=9)
        self.assertEqual(exports[0], exports_base[0])
        # Imports scale with demand, which the barrier also moves: against the EU's, China's fall 40%.
        imports, imports_base = walled.column("imports_by_partner"), base.column("imports_by_partner")
        self.assertAlmostEqual((imports[china] / imports[0]) / (imports_base[china] / imports_base[0]), 0.6, places=9)
        self.assertAlmostEqual(row["customs_duties"], round(0.2 * walled.column("imports_by_partner")[china]), delta=1)
        # They are public receipts, so the budget balance counts them.
        parts = ["income_tax", "national_insurance", "council_tax", "vat", "production_taxes", "corporation_tax",
                 "other_receipts", "customs_duties"]
        self.assertEqual(row["public_receipts"], sum(row[p] for p in parts))
