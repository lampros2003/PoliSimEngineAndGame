"""Target patterns for the toy model (docs/spec/03-toy-model.md).

Each test states something the model must do before any engine work is trusted. Shocked
runs use the same seed as the baseline. Random draws depend only on (seed, stream,
household, step), so a shocked run and the baseline share every draw and differ only
through the policy change. Several tests rely on that to assert exact equalities.
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
TOY = ROOT / "models" / "toy"
SEED = 20261113
SHOCK = 120  # step at which policy changes; the baseline has settled long before
PENCE = 100
G0 = 1_490_000_000  # baseline government purchases, pounds per month


@functools.lru_cache(maxsize=None)
def model():
    return load_model(TOY)


@functools.lru_cache(maxsize=None)
def run(steps: int = 360, seed: int = SEED, preset: str = "central", lever: str | None = None,
        value: float | None = None):
    """Rows of a run in which `lever` is set to `value` at step SHOCK (or never)."""
    commands = {SHOCK: {lever: value}} if lever else None
    return Simulation(model(), seed=seed, preset=preset, commands=commands).run(steps)


def mean(rows, key, start, stop):
    values = [row[key] for row in rows[start:stop]]
    return sum(values) / len(values)


class Accounting(unittest.TestCase):
    def test_every_sector_balance_moves_by_its_net_flows(self):
        rows = run()
        for before, row in zip(rows, rows[1:]):
            households = (row["wages.total"] + row["dividends.total"] + row["benefits.total"]
                          - row["income_tax.total"] - row["consumption.total"])
            firms = (row["consumption.total"] + row["gov_spending"] - row["vat"]
                     - row["wages.total"] - row["dividends.total"])
            government = row["income_tax.total"] + row["vat"] - row["gov_spending"] - row["benefits.total"]
            self.assertEqual(row["hh_money.total"] - before["hh_money.total"], households)
            self.assertEqual(row["firm_money"] - before["firm_money"], firms)
            self.assertEqual(row["gov_money"] - before["gov_money"], government)

    def test_money_issued_equals_money_held_on_every_step(self):
        for row in run():
            self.assertEqual(row["hh_money.total"] + row["firm_money"] + row["gov_money"], 0)

    def test_reported_surplus_is_the_change_in_the_governments_position(self):
        # The "redundant equation": the surplus computed from tax and spending totals
        # must equal the change in the money stock, which is computed from the accounts.
        rows = run()
        for before, row in zip(rows, rows[1:]):
            self.assertEqual(row["gov_balance"], row["gov_money"] - before["gov_money"])

    def test_household_records_add_up_to_the_sector_account(self):
        sim = Simulation(model(), seed=SEED)
        weights = model().entities["household"].weights
        for _ in range(24):
            row = sim.step()
            micro = sum(w * m for w, m in zip(weights, sim.column("hh_money")))
            self.assertEqual(micro, row["hh_money.total"])
            self.assertGreaterEqual(min(sim.column("hh_money")), 0)


class StationaryState(unittest.TestCase):
    def test_unchanged_policy_settles_with_a_balanced_budget(self):
        rows = run()
        gdp = mean(rows, "gdp", SHOCK, 360)
        self.assertLess(abs(mean(rows, "gov_balance", SHOCK, 360)) / gdp, 0.001)
        self.assertTrue(0.04 < mean(rows, "unemployment_rate", SHOCK, 360) < 0.08)
        drift = mean(rows, "gdp", 240, 360) / mean(rows, "gdp", SHOCK, 240)
        self.assertLess(abs(drift - 1.0), 0.005)

    def test_other_seeds_settle_in_the_same_place(self):
        base = run()
        for seed in (1, 2):
            other = run(steps=240, seed=seed)
            self.assertNotEqual(other[0]["hash"], base[0]["hash"])
            self.assertLess(abs(mean(other, "gdp", SHOCK, 240) / mean(base, "gdp", SHOCK, 240) - 1), 0.005)
            self.assertLess(abs(mean(other, "unemployment_rate", SHOCK, 240)
                                - mean(base, "unemployment_rate", SHOCK, 240)), 0.015)


class SpendingRise(unittest.TestCase):
    EXTRA = 100_000_000  # pounds per month

    def setUp(self):
        self.base = run()
        self.up = run(lever="gov_purchases", value=G0 + self.EXTRA)

    def test_first_month_output_rises_by_exactly_the_extra_spending(self):
        # Hiring responds to last month's sales, so nothing else can move yet.
        self.assertEqual(self.up[SHOCK]["gdp"] - self.base[SHOCK]["gdp"], self.EXTRA * PENCE)
        self.assertEqual(self.up[SHOCK - 1]["hash"], self.base[SHOCK - 1]["hash"])

    def test_long_run_multiplier_is_about_two(self):
        gain = mean(self.up, "gdp", 240, 360) - mean(self.base, "gdp", 240, 360)
        self.assertTrue(1.8 < gain / (self.EXTRA * PENCE) < 2.2)

    def test_the_budget_returns_to_balance(self):
        change = mean(self.up, "gov_balance", 240, 360) - mean(self.base, "gov_balance", 240, 360)
        self.assertLess(abs(change) / (self.EXTRA * PENCE), 0.05)

    def test_unemployment_falls(self):
        self.assertLess(mean(self.up, "unemployment_rate", 240, 360),
                        mean(self.base, "unemployment_rate", 240, 360) - 0.02)


class SpendingCut(unittest.TestCase):
    CUT = 150_000_000

    def setUp(self):
        self.base = run()
        self.cut = run(lever="gov_purchases", value=G0 - self.CUT)

    def improvement(self, start, stop):
        gap = mean(self.cut, "gov_balance", start, stop) - mean(self.base, "gov_balance", start, stop)
        return gap / (self.CUT * PENCE)

    def test_budget_improves_by_the_full_cut_only_in_the_first_month(self):
        self.assertEqual(self.cut[SHOCK]["gov_balance"] - self.base[SHOCK]["gov_balance"], self.CUT * PENCE)
        self.assertTrue(0.2 < self.improvement(SHOCK + 1, SHOCK + 4) < 0.6)

    def test_automatic_stabilisers_undo_the_saving(self):
        self.assertLess(abs(self.improvement(240, 360)), 0.05)
        self.assertGreater(mean(self.cut, "benefits_total", 240, 360),
                           mean(self.base, "benefits_total", 240, 360) * 1.3)
        self.assertGreater(mean(self.cut, "unemployment_rate", 240, 360),
                           mean(self.base, "unemployment_rate", 240, 360) + 0.03)


class TaxChanges(unittest.TestCase):
    def test_a_higher_basic_rate_shrinks_output_and_employment(self):
        base, tax = run(), run(lever="basic_rate", value=0.25)
        self.assertLess(mean(tax, "gdp", 240, 360) / mean(base, "gdp", 240, 360), 0.98)
        self.assertGreater(mean(tax, "unemployment_rate", 240, 360),
                           mean(base, "unemployment_rate", 240, 360) + 0.01)

    def test_a_higher_top_rate_costs_only_households_above_the_threshold(self):
        weights = model().entities["household"].weights
        threshold = 4000 * PENCE
        base = Simulation(model(), seed=SEED)
        shock = Simulation(model(), seed=SEED, commands={SHOCK: {"higher_rate": 0.50}})
        base.run(SHOCK + 1)
        shock.run(SHOCK + 1)
        income = base.column("market_income")
        self.assertEqual(income, shock.column("market_income"))
        before, after = base.column("disposable_income"), shock.column("disposable_income")
        losers = 0
        for gross, old, new in zip(income, before, after):
            self.assertLessEqual(new, old)  # nobody gains in the month of the change
            if gross <= threshold:
                self.assertEqual(new, old)
            elif gross >= threshold + 100 * PENCE:
                self.assertLess(new, old)
                losers += 1
        self.assertGreater(losers, 50)

        def top_tenth_share(disposable):
            ranked = sorted(zip(disposable, weights), reverse=True)
            cutoff = sum(weights) // 10
            seen = held = 0
            for amount, weight in ranked:
                take = min(weight, cutoff - seen)
                if take <= 0:
                    break
                held += take * amount
                seen += take
            return held / sum(a * w for a, w in zip(disposable, weights))

        self.assertLess(top_tenth_share(after), top_tenth_share(before))


class Thrift(unittest.TestCase):
    def test_saving_more_cuts_output_now_but_not_in_the_long_run(self):
        base, thrifty = run(), run(steps=240, preset="low")
        self.assertLess(mean(thrifty, "gdp", 0, 12) / mean(base, "gdp", 0, 12), 0.97)
        self.assertLess(abs(mean(thrifty, "gdp", 180, 240) / mean(base, "gdp", 180, 240) - 1), 0.005)
        # Money held settles at (1 - propensity_income) / propensity_wealth months of
        # income: 3 months instead of 2.
        ratio = mean(thrifty, "hh_money.total", 180, 240) / mean(base, "hh_money.total", 180, 240)
        self.assertLess(abs(ratio - 1.5), 0.015)


class Reproducibility(unittest.TestCase):
    def test_baseline_matches_the_recorded_hashes(self):
        # This is the cross-machine test: the recorded file was produced once and every
        # platform and Python version must reproduce it on every step.
        with open(TOY / "golden" / "baseline.hashes.csv", newline="", encoding="utf-8") as handle:
            golden = [row["hash"] for row in csv.DictReader(handle)]
        self.assertEqual(len(golden), 240)
        self.assertEqual([row["hash"] for row in run()[:240]], golden)

    def test_two_runs_with_one_seed_are_identical(self):
        first = Simulation(model(), seed=7).run(36)
        second = Simulation(model(), seed=7).run(36)
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
