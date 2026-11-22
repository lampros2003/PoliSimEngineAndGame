"""Stage S14.5: the economy (docs/S14-PLAN.md, "The economy"). Each class states one
mechanism in plain words and checks it on the engine, from the 2025 scenario's parameters.
Every new term is nil in the base month (tests/test_uk.py checks the 2024 accounts)."""

from __future__ import annotations

import functools
import sys
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from engine import Simulation, load_model  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
UK = ROOT / "models" / "uk"
SEED = 2025
PARAMS = tomllib.loads((UK / "scenarios" / "2025.toml").read_text(encoding="utf-8"))["params"]


@functools.lru_cache(maxsize=None)
def model():
    return load_model(UK)


def default(name):
    return model().symbols[name].spec["default"]


def setting(name, value):
    """A money lever's factor on its default as pounds (pounds as given where the default is
    nothing); anything else as given."""
    return round(default(name) * value) if model().symbols[name].money and default(name) else value


@functools.lru_cache(maxsize=None)
def run(commands: tuple = (), steps: int = 25, params: tuple = ()):
    """Every month's row. `commands` is ((step, name, value), ...), a money lever's value its
    factor on the default; no question is answered."""
    by_step: dict[int, dict] = {}
    for step, name, value in commands:
        by_step.setdefault(step, {})[name] = setting(name, value)
    sim = Simulation(model(), seed=SEED, params={**PARAMS, **dict(params)}, commands=by_step)
    return sim.run(steps)


class TaxRise(unittest.TestCase):
    """S13-BALANCE item 5: a 10-point basic rate rise seemed first to worsen the deficit. The
    cause was the question it brings: the slump it causes opens "a bank in trouble", and the
    first answer (a rescue) doubles subsidies for six months, about £19bn. The rise itself
    improves the balance from its first month, so the model was right and nothing is changed."""

    def test_a_ten_point_rise_improves_the_balance_every_month_for_two_years(self):
        base, taxed = run(), run(((1, "basic_rate", 0.30),))
        for month in range(1, 25):
            self.assertGreater(taxed[month]["budget_balance"], base[month]["budget_balance"], month)


class PensionerPoverty(unittest.TestCase):
    """S13-BALANCE item 3: pensioners all held the same State Pension, so a block of them
    crossed the poverty line together. Their State Pensions are now spread as DWP's caseload
    is (households.py, `state_pension_spread`) and follow the benefits bill."""

    def test_the_state_pension_total_is_unchanged(self):
        rows = run(steps=1)
        self.assertEqual(rows[0]["state_pension_level"], 1.0)

    def test_each_point_of_state_pension_moves_pensioner_poverty_by_under_a_point(self):
        rates = [run(((1, "benefits_bill", 1 - k / 100),), steps=2)[1]["pensioner_poverty_rate"] for k in range(11)]
        for a, b in zip(rates, rates[1:]):
            self.assertGreaterEqual(b, a)
            self.assertLess(b - a, 0.01)
        self.assertGreater(rates[-1] - rates[0], 0.02)  # a tenth off the pension is felt

    def test_a_tenth_off_over_ten_months_moves_it_by_under_a_point_a_month(self):
        rows = run(tuple((month, "benefits_bill", 1 - month / 100) for month in range(1, 11)), steps=14)
        moves = [abs(rows[i]["pensioner_poverty_rate"] - rows[i - 1]["pensioner_poverty_rate"]) for i in range(1, 14)]
        self.assertLess(max(moves), 0.01)


PRICE_SHOCK = tuple((month, "inflation_shock", 0.002) for month in range(1, 7))  # prices 1.2% higher over six months
BORROW = ((1, "benefits_bill", 1.4),)  # two fifths more on pensions and benefits, borrowed


class InterestRates(unittest.TestCase):
    """A Bank Rate set by a rule, a gilt yield and a mortgage rate that follow it, and what
    households, firms and the Treasury pay as they move (finances.toml)."""

    def test_the_base_month_has_2024_rates_and_nothing_moves(self):
        first = run(steps=1)[0]
        self.assertEqual(first["bank_rate"], 0.0475)
        self.assertEqual(first["mortgage_rate"], 0.038)
        for flow in ("mortgage_interest_rise", "mortgage_interest_fall", "firm_interest_rise", "firm_interest_fall",
                     "reserves_interest"):
            self.assertEqual(first[flow], 0, flow)
        self.assertEqual(first["investment_rate_factor"], 1.0)
        self.assertEqual(first["gilt_yield_now"], model().symbols["gilt_yield"].spec["central"])

    def test_the_bank_raises_rates_against_inflation_and_within_its_bounds(self):
        base, shocked = run(), run(PRICE_SHOCK)
        self.assertGreater(shocked[8]["bank_rate"], base[8]["bank_rate"] + 0.005)
        for row in shocked:
            self.assertGreaterEqual(row["bank_rate"], 0.001)
            self.assertLessEqual(row["bank_rate"], 0.15)
        # A sixth of the way a month: never more than the Bank's largest step since 1992,
        # three quarters of a point (November 2022).
        moves = [abs(shocked[i]["bank_rate"] - shocked[i - 1]["bank_rate"]) for i in range(1, 25)]
        self.assertLess(max(moves), 0.0075)

    def test_the_bank_cuts_rates_in_a_slump(self):
        base, slump = run(), run(((1, "spending_health", 0.75),))
        self.assertLess(slump[12]["bank_rate"], base[12]["bank_rate"] - 0.005)

    def test_mortgages_follow_bank_rate_and_gilts_slowly(self):
        base, shocked = run(), run(PRICE_SHOCK)
        rise = [s["mortgage_rate"] - b["mortgage_rate"] for s, b in zip(shocked, base)]
        bank = shocked[8]["bank_rate"] - base[8]["bank_rate"]
        self.assertGreater(rise[8], 0.0)
        self.assertLess(rise[8], bank / 3)  # most mortgages are fixed: little has passed through in eight months
        self.assertGreater(shocked[8]["mortgage_rate_new"] - base[8]["mortgage_rate_new"], bank / 3)
        self.assertGreater(shocked[8]["gilt_yield_now"], base[8]["gilt_yield_now"])

    def test_higher_rates_cost_mortgagors_more_than_pensioners_and_reach_voters(self):
        rows = run(PRICE_SHOCK, steps=19)
        sim = Simulation(model(), seed=SEED, params=PARAMS,
                         commands={m: {"inflation_shock": 0.002} for m in range(1, 7)})
        sim.run(19)
        cost, age = sim.column("mortgage_cost_change"), sim.column("age1")
        young = [c for c, a in zip(cost, age) if 35 <= a < 50]
        old = [c for c, a in zip(cost, age) if a >= 70]
        self.assertGreater(sum(young) / len(young), 10 * sum(old) / len(old))
        self.assertGreater(rows[-1]["mortgage_interest_rise"], 0)
        self.assertGreater(rows[-1]["firm_interest_rise"], 0)
        self.assertGreater(rows[-1]["reserves_interest"], 0)

    def test_dearer_borrowing_lowers_business_investment(self):
        base, dear = run(), run(((1, "gilt_yield_shift", 0.02),))  # gilt yields two points higher
        self.assertLess(dear[24]["investment_rate_factor"], 0.975)
        self.assertLess(dear[24]["business_investment"], base[24]["business_investment"] * 0.98)

    def test_the_lenders_premium_reaches_new_mortgages(self):
        base, borrowed = run(), run(BORROW)
        self.assertGreater(borrowed[-1]["gilt_premium"], 0.005)
        self.assertGreater(borrowed[-1]["mortgage_rate_new"], base[-1]["mortgage_rate_new"] + 0.002)


class SlumpsThatLast(unittest.TestCase):
    """Firms hoard labour and shed it later, long unemployment raises the natural rate for a
    time, and pay is slow to fall (labour.toml): a slump's unemployment outlasts it."""

    SHOCK = ((1, "investment_demand", 0.75), (13, "investment_demand", 1.0))  # a year of business investment a quarter down

    def test_nothing_moves_in_the_base_month(self):
        first = run(steps=1)[0]
        self.assertEqual(first["long_unemployment"], 0.0)
        self.assertEqual(first["natural_unemployment_now"], model().symbols["natural_unemployment"].spec["central"])

    def test_after_a_year_long_slump_unemployment_peaks_late_and_stays_up(self):
        base, slump = run(steps=37), run(self.SHOCK, steps=37)
        output = [s["real_gdp"] / b["real_gdp"] for s, b in zip(slump, base)]
        unemployment = [s["unemployment_rate"] for s in slump]
        self.assertGreater(unemployment.index(max(unemployment)), output.index(min(output)))
        self.assertGreater(unemployment[25], unemployment[0])  # two years on, above its start
        self.assertGreater(slump[18]["unemployment_rate"], base[18]["unemployment_rate"])  # and above doing nothing half a year after
        self.assertGreater(slump[13]["natural_unemployment_now"], base[13]["natural_unemployment_now"])


class BorrowingCliff(unittest.TestCase):
    """Lenders refuse the gilts by chance, a chance that rises smoothly with borrowing above
    its level at the start (finances.toml, gilt_crisis_odds), and voters' dislike of borrowing
    steepens smoothly, with no kink (politics.toml, finances_reaction)."""

    def curve(self, table, x):
        sim = Simulation(model(), seed=SEED)
        return sim.evaluate(f"curve({x!r}, {table})")

    def test_the_chance_is_nil_at_the_start_small_at_a_point_and_near_certain_in_a_year_at_three(self):
        self.assertEqual(self.curve("gilt_crisis_odds", 0.0), 0.0)
        self.assertEqual(self.curve("gilt_crisis_odds", -0.01), 0.0)
        self.assertLess(self.curve("gilt_crisis_odds", 0.01), 0.03)
        self.assertGreater(1 - (1 - self.curve("gilt_crisis_odds", 0.03)) ** 12, 0.9)

    def test_both_curves_rise_smoothly_and_ever_more_steeply(self):
        for table, sign in (("gilt_crisis_odds", 1), ("finances_reaction", -1)):
            values = [sign * self.curve(table, k / 1000) for k in range(0, 31)]
            steps = [b - a for a, b in zip(values, values[1:])]
            for a, b in zip(steps, steps[1:]):
                self.assertGreaterEqual(b, a - 1e-12, table)  # convex: never a step smaller than the last
            self.assertLess(max(steps), 3 * steps[len(steps) // 2], table)  # and no cliff

    def test_borrowing_just_under_the_old_line_no_longer_escapes(self):
        # Pensions and benefits a fifth higher, borrowed: about 1.1 points above the start by the
        # third year, under S13.8's line of 1.2. Most seeds now meet the crisis before the election.
        met = 0
        for seed in range(1, 13):
            sim = Simulation(model(), seed=seed, params=PARAMS, commands={1: {"benefits_bill": setting("benefits_bill", 1.22)}})
            rows = sim.run(54)
            self.assertLess(max(r["borrowing_gap"] for r in rows), 0.012)
            met += any(r["gilt_crisis_open"] for r in rows)
        self.assertGreaterEqual(met, 6)


class Homelessness(unittest.TestCase):
    """Households in temporary accommodation (statistics.toml): 126,040 in England on
    30 September 2024; fewer with rent controls, homes built and social housing, more with poverty,
    unemployment and dearer mortgages."""

    def test_the_base_month_is_the_published_figure(self):
        first = run(steps=1)[0]
        self.assertEqual(first["homelessness"], 126040.0)
        self.assertFalse(first["homelessness_rising"])

    def test_rent_controls_and_social_housing_each_lower_it_visibly(self):
        base = run(steps=54)
        for change in (((1, "rent_controls", 2),), ((1, "social_housing", 300_000_000),), ((1, "planning_rules", 4),)):
            rows = run(change, steps=54)
            self.assertLess(rows[53]["homelessness"], base[53]["homelessness"] * 0.97, change)

    def test_a_slump_raises_it_and_says_so(self):
        base, slump = run(steps=25), run(((1, "spending_health", 0.75),), steps=25)
        self.assertGreater(slump[24]["homelessness"], base[24]["homelessness"] * 1.04)
        self.assertTrue(any(r["homelessness_rising"] for r in slump))


class Productivity(unittest.TestCase):
    """Output per job against 2024 = 100 (statistics.toml): it follows business and public
    investment, school results and healthy life over about five years, and pay and exports
    follow it."""

    def test_the_base_month_is_100_and_doing_nothing_keeps_it_near(self):
        rows = run(steps=54)
        self.assertEqual(rows[0]["productivity"], 100.0)
        self.assertLess(max(abs(r["productivity"] - 100.0) for r in rows), 0.2)

    def test_public_investment_raises_it_slowly_and_pay_follows(self):
        base, invest = run(steps=54), run(((1, "public_investment_bill", 1.5),), steps=54)
        self.assertLess(invest[12]["productivity"], 100.5)  # slowly
        self.assertGreater(invest[53]["productivity"], base[53]["productivity"] + 0.5)
        self.assertGreater(invest[53]["private_pay_per_worker"], base[53]["private_pay_per_worker"])

    def test_a_health_cut_lowers_it(self):
        base, cut = run(steps=54), run(((1, "spending_health", 0.75),), steps=54)
        self.assertLess(cut[53]["productivity"], base[53]["productivity"])


if __name__ == "__main__":
    unittest.main()
