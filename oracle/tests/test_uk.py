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
        first = sum(r["gdp_2024_prices"] for r in rows[:12])
        last = sum(r["gdp_2024_prices"] for r in rows[-12:])
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
