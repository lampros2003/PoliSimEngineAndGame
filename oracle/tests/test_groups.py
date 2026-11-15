"""The UK's interest groups (docs/S13-PLAN.md, milestone S13.4): each group's share of the
electorate, its approval of the government and the drivers of that approval, written by
tools/uk/voters.py into models/uk/politics.toml (models/uk/politics/README.md, Groups)."""

from __future__ import annotations

import functools
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from polisim_oracle import Simulation, load_model  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
UK = ROOT / "models" / "uk"
SEED = 2025
GROUPS = ["young", "midlife", "pensioners", "low_income", "middle_income", "high_income", "in_work", "out_of_work",
          "parents", "lone_parents", "self_employed", "scotland", "wales", "northern_ireland", "london", "north",
          "midlands", "south",
          # Stage S13.5: estimated from published shares (models/uk/POLICIES.md, Groups).
          "motorists", "home_owners", "renters", "drinkers", "smokers"]
PARTITIONS = {"age": ["young", "midlife", "pensioners"],
              "income": ["low_income", "middle_income", "high_income"],
              "place": ["scotland", "wales", "northern_ireland", "london", "north", "midlands", "south"],
              "tenure": ["home_owners", "renters"]}
DRIVERS = ["income", "jobs", "prices_and_time", "services", "standing"]
OPTIONS = 10  # nine blocs and not voting, the last
YEAR = 13  # the base month and a year after a change made in the second


@functools.lru_cache(maxsize=None)
def model():
    return load_model(UK)


@functools.lru_cache(maxsize=None)
def first_month():
    sim = Simulation(model(), seed=SEED)
    row = sim.step()
    return sim, row


@functools.lru_cache(maxsize=None)
def after_a_year(**levers):
    """The simulation and its row a year after the levers change, in the second month."""
    sim = Simulation(model(), seed=SEED, commands={1: levers} if levers else None)
    rows = sim.run(YEAR)
    return sim, rows[-1]


def likely_voters(sim) -> list[float]:
    """Each group's adults who would vote, from the voter types."""
    voters, member, choice = sim.column("voters"), sim.column("group_member"), sim.column("choice")
    return [sum(voters[t] * member[t * len(GROUPS) + g] * (1.0 - choice[t * OPTIONS + OPTIONS - 1])
                for t in range(len(voters))) for g in range(len(GROUPS))]


class BaseMonth(unittest.TestCase):
    def test_the_partitions_cover_the_electorate(self):
        _, row = first_month()
        for name, groups in PARTITIONS.items():
            self.assertAlmostEqual(sum(row[f"share_{g}"] for g in groups), 1.0, places=12, msg=name)

    def test_approvals_weighted_by_likely_voters_give_the_poll_rating(self):
        sim, row = first_month()
        likely = likely_voters(sim)
        for name, groups in PARTITIONS.items():
            weights = [likely[GROUPS.index(g)] for g in groups]
            mean = sum(w * row[f"approval_{g}"] for w, g in zip(weights, groups)) / sum(weights)
            self.assertAlmostEqual(mean, row["government_support"], places=12, msg=name)

    def test_the_rows_match_the_bars(self):
        sim, row = first_month()
        approval, share = sim.column("group_approval"), sim.column("group_share")
        for g, key in enumerate(GROUPS):
            self.assertEqual(row[f"approval_{key}"], approval[g])
            self.assertEqual(row[f"share_{key}"], share[g])

    def test_the_drivers_start_at_zero(self):
        sim, _ = first_month()
        for driver in DRIVERS:
            self.assertEqual(sim.column(f"group_driver_{driver}"), [0.0] * len(GROUPS), driver)

    def test_the_shares_are_plausible(self):
        _, row = first_month()
        # About 29% of adults live with children under 16 or 17 in the households (the
        # Labour Force Survey's families put it near 30%); about 3.6% are lone parents.
        self.assertGreater(row["share_parents"], 0.25)
        self.assertLess(row["share_parents"], 0.35)
        self.assertGreater(row["share_lone_parents"], 0.02)
        self.assertLess(row["share_lone_parents"], 0.06)
        self.assertGreater(row["share_pensioners"], 0.2)
        self.assertLess(row["share_pensioners"], 0.3)
        # Stage S13.5: the estimated groups hold their published shares of all adults where one
        # is given (smokers 10.6%, home owners 65%), give or take the cap at 98% and the
        # households' reweighting in the first month.
        self.assertAlmostEqual(row["share_smokers"], 0.106, places=2)
        self.assertAlmostEqual(row["share_home_owners"], 0.65, places=2)
        self.assertGreater(row["share_motorists"], 0.7)
        self.assertLess(row["share_motorists"], 0.85)


class Drivers(unittest.TestCase):
    def test_the_drivers_add_up_to_the_performance_part_of_utility(self):
        """After a year, each group's drivers add up to its adults' mean of the governing
        blocs' performance utility (income, then the fundamentals), less the base month's
        time in office, which the intercepts absorb."""
        sim, _ = after_a_year(basic_rate=0.25)
        voters, member = sim.column("voters"), sim.column("group_member")
        income, rest = sim.column("voter_income_change"), sim.column("voter_fundamentals")
        effect = sim.evaluate("vote_income_effect")
        base_tenure = sim.evaluate("vote_tenure_effect") * 6 / 12.0
        drivers = {d: sim.column(f"group_driver_{d}") for d in DRIVERS}
        for g, key in enumerate(GROUPS):
            weights = [voters[t] * member[t * len(GROUPS) + g] for t in range(len(voters))]
            mean = sum(w * (effect * income[t] + rest[t]) for t, w in enumerate(weights)) / sum(weights)
            self.assertAlmostEqual(sum(drivers[d][g] for d in DRIVERS), mean - base_tenure, places=12, msg=key)
            self.assertNotEqual(drivers["income"][g], 0.0, key)


class Policies(unittest.TestCase):
    def change(self, key: str, **levers) -> float:
        return after_a_year(**levers)[1][f"approval_{key}"] - after_a_year()[1][f"approval_{key}"]

    def test_a_higher_basic_rate_costs_more_among_high_incomes(self):
        high, low = self.change("high_income", basic_rate=0.25), self.change("low_income", basic_rate=0.25)
        self.assertLess(high, 0.0)
        self.assertLess(high, low)

    def test_no_child_benefit_costs_parents_more_than_pensioners(self):
        # Stage S13.4: the State Pension age does not move pensioners' approval: in the model it
        # only bounds Universal Credit, which pensions mostly exhaust. Child Benefit is the lever
        # that clearly hits one group.
        cut = {"child_benefit_eldest": 0, "child_benefit_other": 0}
        parents, pensioners = self.change("parents", **cut), self.change("pensioners", **cut)
        self.assertLess(parents, -0.005)
        self.assertLess(parents, pensioners)


if __name__ == "__main__":
    unittest.main()
