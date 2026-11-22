"""Stage S13.8: the public finances matter (docs/S13-PLAN.md). Lenders ask more for new gilts
when borrowing runs above its level at the start, voters weigh borrowing against the last
election, and lenders refuse the gilts when borrowing stays far above the start
(models/uk/finances.toml, politics.toml, dilemmas.toml; politics/README.md, "The public
finances"). Each run starts from the 2025 scenario's parameters, which switch the lenders and
the voters on; without them every term is nil."""

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
TWO_YEARS = 25  # the base month and two years after a change made in the second
PARAMS = tomllib.loads((UK / "scenarios" / "2025.toml").read_text(encoding="utf-8"))["params"]


@functools.lru_cache(maxsize=None)
def model():
    return load_model(UK)


BORROW = (("benefits_bill", 1.4),)  # two fifths more on pensions and benefits, borrowed (a bill of 41)
CONSOLIDATE = (("basic_rate", 0.28), ("vat_rate", 0.25))  # taxes up to pay down borrowing


@functools.lru_cache(maxsize=None)
def run(changes: tuple = (), with_params: bool = True, steps: int = TWO_YEARS):
    """The rows of every month with `changes` from the second month: a money lever's factor
    on its default, a rate's new value."""
    levers = {}
    for name, value in changes:
        spec = model().symbols[name].spec
        levers[name] = round(spec["default"] * value) if isinstance(spec["default"], int) else value
    sim = Simulation(model(), seed=SEED, params=dict(PARAMS) if with_params else None,
                     commands={1: levers} if levers else None)
    return sim, sim.run(steps)


def mean_finances(sim) -> float:
    """The voters' public finances term, averaged over the adults."""
    voters, term = sim.column("voters"), sim.column("voter_finances")
    return sum(v * t for v, t in zip(voters, term)) / sum(voters)


class Lenders(unittest.TestCase):
    def test_nothing_moves_in_the_base_month(self):
        _, rows = run(steps=1)
        first = rows[0]
        self.assertEqual(first["gilt_premium"], 0.0)
        self.assertEqual(first["borrowing_gap"], 0.0)
        self.assertEqual(first["gilt_yield_now"], model().symbols["gilt_yield"].spec["central"])
        self.assertFalse(first["lenders_confidence"])
        self.assertFalse(first["gilt_crisis_open"])

    def test_borrowing_to_spend_raises_the_yield_and_costs_standing_within_two_years(self):
        (_, base), (sim, rows) = run(), run(BORROW)
        self.assertGreater(rows[-1]["borrowing_gap"], base[-1]["borrowing_gap"] + 0.01)
        self.assertGreater(rows[-1]["gilt_premium"], 0.005)
        self.assertGreater(rows[-1]["gilt_yield_now"], base[-1]["gilt_yield_now"])
        self.assertGreater(rows[-1]["effective_rate"], base[-1]["effective_rate"])
        self.assertLess(mean_finances(sim), mean_finances(run()[0]))
        self.assertLess(mean_finances(sim), -0.05)
        # Pensioners weigh it more than the young.
        groups = model().dims["group"].members
        driver = sim.column("group_driver_finances")
        self.assertLess(driver[groups.index("pensioner")], driver[groups.index("young")])

    def test_a_consolidation_does_the_reverse(self):
        (_, base), (sim, rows) = run(), run(CONSOLIDATE)
        self.assertLess(rows[-1]["borrowing_gap"], -0.01)
        self.assertLess(rows[-1]["gilt_premium"], 0.0)
        self.assertLess(rows[-1]["gilt_yield_now"], base[-1]["gilt_yield_now"])
        self.assertGreater(mean_finances(sim), 0.0)
        self.assertTrue(rows[-1]["lenders_confidence"])
        self.assertGreater(rows[-1]["finances_standing"], 0.0)

    def test_without_the_scenario_parameters_lenders_and_voters_do_not_mind(self):
        sim, rows = run(BORROW, with_params=False)
        self.assertEqual({row["gilt_premium"] for row in rows}, {0.0})
        self.assertEqual(set(sim.column("voter_finances")), {0.0})


class Crisis(unittest.TestCase):
    def test_lenders_refuse_under_sustained_heavy_borrowing_and_not_under_defaults(self):
        _, heavy = run(BORROW)
        _, base = run()
        opened = [k for k, row in enumerate(heavy) if row["gilt_crisis_open"]]
        self.assertTrue(opened, "the crisis did not open in two years of heavy borrowing")
        self.assertGreaterEqual(opened[0], 12)
        self.assertFalse(any(row["gilt_crisis_open"] for row in base))


if __name__ == "__main__":
    unittest.main()
