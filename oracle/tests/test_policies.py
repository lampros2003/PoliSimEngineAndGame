"""The UK's real policies and the indicators they move (docs/S13-PLAN.md, milestone S13.5),
in models/uk/policies.toml (from tools/uk/template/policies.toml; models/uk/POLICIES.md).

Each policy is moved from its 2024 setting at the start and the model run for a year. To keep
the suite's time down, three runs move several policies at once, chosen so that no two in a
run push the same value: each test reads a value only one policy of its run moves, or several
that the doc texts say move it the same way."""

from __future__ import annotations

import csv
import functools
import math
import sys
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from polisim_oracle import Simulation, load_model  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
UK = ROOT / "models" / "uk"
SEED = 2025
YEAR = 13  # the base month and a year
FIVE_YEARS = 61
LEVERS = tomllib.loads((UK / "policies.toml").read_text(encoding="utf-8"))["lever"]
GROUPS = ["young", "midlife", "pensioners", "low_income", "middle_income", "high_income", "in_work", "out_of_work",
          "parents", "lone_parents", "self_employed", "scotland", "wales", "northern_ireland", "london", "north",
          "midlands", "south", "motorists", "home_owners", "renters", "drinkers", "smokers"]

ONE = {"sentencing": 3, "tobacco_duty": 1.5, "ev_grant": 3000, "planning_rules": 3, "free_school_meals": 1,
       "winter_fuel_payment": 2, "visa_threshold": 50000, "prescription_charge": 12}
TWO = {"drinking_age": 20, "fuel_duty": 60.0, "insulation_programme": 166666666.67, "tuition_fee_cap": 11000,
       "social_housing": 166666666.67, "bus_fare_cap": 1.5, "sugar_levy": 2.0}
THREE = {"alcohol_duty": 1.5, "cannabis_law": 2, "rent_controls": 2, "petrol_ban_year": 2028}
RUNS = {"one": ONE, "two": TWO, "three": THREE, "base": {}}


@functools.lru_cache(maxsize=None)
def model():
    return load_model(UK)


@functools.lru_cache(maxsize=None)
def run(name: str, steps: int = YEAR):
    """The simulation and its rows with a run's policies set from the start."""
    sim = Simulation(model(), seed=SEED, levers=dict(RUNS[name]) or None)
    return sim, sim.run(steps)


@functools.lru_cache(maxsize=None)
def extreme(end: int, steps: int = FIVE_YEARS):
    """Every policy at one end of its range (0 the bottom, 1 the top) for five years."""
    sim = Simulation(model(), seed=SEED, levers={k: spec["range"][end] for k, spec in LEVERS.items()})
    return sim, sim.run(steps)


def after(name: str, column: str) -> float:
    return run(name)[1][-1][column]


def change(name: str, column: str) -> float:
    return after(name, column) - after("base", column)


class Neutral(unittest.TestCase):
    def test_every_policy_at_its_default_gives_the_recorded_hashes(self):
        sim = Simulation(model(), seed=SEED, levers={k: spec["default"] for k, spec in LEVERS.items()})
        with open(UK / "golden" / "2025.hashes.csv", newline="", encoding="utf-8") as handle:
            golden = [row["hash"] for row in csv.DictReader(handle)][:3]
        self.assertEqual([row["hash"] for row in sim.run(3)], golden)

    def test_the_hooks_are_nil_at_the_defaults(self):
        _, rows = run("base")
        for name in ("policy_duties", "policy_charges", "policy_purchases", "policy_investment", "policy_subsidies",
                     "policy_benefits"):
            self.assertEqual({row[name] for row in rows}, {0}, name)
        for name in ("homes_policy_level", "crime_policy_level", "household_emissions_factor", "health_demand_factor",
                     "policy_migration_factor"):
            self.assertEqual({row[name] for row in rows}, {1.0}, name)
        self.assertEqual({row["policy_labour_force_growth"] for row in rows}, {0.0})

    def test_the_indicators_start_at_their_2024_levels(self):
        _, rows = run("base")
        first = rows[0]
        self.assertAlmostEqual(first["crime_incidents"] / 9.2e6, 1.0, places=3)
        self.assertAlmostEqual(first["healthy_life_expectancy"], 60.8, places=2)
        self.assertAlmostEqual(first["school_attainment"], 0.459, places=3)
        self.assertEqual(first["homes_built"], 221070.0)
        self.assertEqual(first["net_migration_annual"], 739015.0)
        self.assertEqual(first["ev_share"], 0.191)


class Money(unittest.TestCase):
    """A duty's receipts appear in the budget; a grant's cost appears as spending."""

    # Each flow without its policy term: a formula as the flow has it, and whether the flow
    # scales it by the trend index (which the step has since moved on, so it is taken from the
    # month before), then the rest of the flow.
    HOOKS = {"production_taxes": ("1.0 * production_tax_rate * private_demand", False, "0", "policy_duties"),
             "other_receipts": ("1.0 * other_receipts_share * private_demand", False, "0", "policy_charges"),
             "procurement": ("1.0 * procurement_bill", True, "0", "policy_purchases"),
             "public_investment": ("1.0 * public_investment_bill", True, "0", "policy_investment"),
             "subsidies": ("1.0 * subsidies_bill", True, "0", "policy_subsidies"),
             "benefits": ("benefits_bill + benefit_per_unemployed * unemployed", True,
                          "child_benefit_total + universal_credit_total", "policy_benefits")}

    def test_each_hook_adds_its_policies_money_to_its_flow(self):
        for name in ("one", "two", "three"):
            sim, rows = run(name)
            row, trend = rows[-1], rows[-2]["trend_index"]
            for flow, (formula, scaled, rest, term) in self.HOOKS.items():
                value = sim.evaluate(formula, unit="GBP/month")
                base = round(value * trend if scaled else value) + sim.evaluate(rest, type="int", unit="GBP/month")
                self.assertEqual(row[flow], base + row[term], f"{name}: {flow}")

    def test_the_aggregates_add_up(self):
        for name in ("one", "two", "three"):
            row = run(name)[1][-1]
            self.assertEqual(row["policy_duties"], row["fuel_duty_change"] + row["alcohol_duty_change"]
                             + row["tobacco_duty_change"] + row["sugar_levy_change"] + row["cannabis_tax_receipts"])
            self.assertEqual(row["policy_purchases"], row["prison_cost_change"] + row["tuition_cost_change"]
                             + row["school_meals_cost"])
            self.assertEqual(row["policy_investment"], row["insulation_cost"] + row["social_housing_cost"])
            self.assertEqual(row["policy_subsidies"], row["ev_grant_cost"] + row["bus_fare_cost_change"])

    def test_receipts_rise_with_higher_duties_and_charges(self):
        for name, column in (("two", "fuel_duty_change"), ("three", "alcohol_duty_change"),
                             ("one", "tobacco_duty_change"), ("two", "sugar_levy_change"),
                             ("three", "cannabis_tax_receipts"), ("one", "prescription_charge_change")):
            self.assertGreater(after(name, column), 0, column)
        self.assertGreater(change("two", "public_receipts"), 0)

    def test_spending_policies_cost_money(self):
        for name, column in (("one", "prison_cost_change"), ("one", "ev_grant_cost"), ("one", "school_meals_cost"),
                             ("one", "winter_fuel_change"), ("two", "insulation_cost"), ("two", "tuition_cost_change"),
                             ("two", "social_housing_cost"), ("two", "bus_fare_cost_change")):
            self.assertGreater(after(name, column), 0, column)
        # The insulation and social housing programmes, £2bn a year each in 2024 prices.
        rows = run("two")[1]  # the cost reads the trend index as it stood at the start of the month
        self.assertAlmostEqual(rows[-1]["insulation_cost"] * 12 / 100 / rows[-2]["trend_index"] / 2e9, 1.0, places=6)


class Effects(unittest.TestCase):
    """What each lever's doc text says it does, after a year."""

    def test_law_and_order(self):
        self.assertGreater(change("one", "prison_population"), 2000)   # sentencing one step tougher
        self.assertLess(change("one", "crime_incidents"), 0)
        self.assertLess(change("two", "alcohol_use"), 0)               # drinking age 20
        self.assertLess(change("two", "crime_incidents"), 0)
        self.assertLess(after("three", "crime_policy_target"), 1.0)    # alcohol duty and legal cannabis

    def test_health(self):
        self.assertLess(change("one", "smoking_prevalence"), 0)        # tobacco duty
        self.assertGreater(change("one", "healthy_life_expectancy"), 0)
        self.assertLess(change("one", "referrals"), 0)
        self.assertLess(after("one", "hle_other"), 0.0)                # a dearer prescription
        self.assertLess(change("three", "alcohol_use"), 0)             # alcohol duty
        self.assertLess(change("three", "alcohol_deaths"), 0)
        self.assertGreater(after("two", "hle_other"), 0.0)             # a higher soft drinks levy
        self.assertLess(after("three", "hle_other"), 0.0)              # legal cannabis

    def test_transport_and_energy(self):
        self.assertLess(change("two", "fuel_volume"), 0)               # fuel duty
        self.assertGreater(change("two", "tax_wedge"), 0)
        self.assertGreater(change("two", "ev_share"), 0)
        self.assertGreater(change("one", "ev_share"), 0.02)            # a £3,000 grant
        self.assertLess(after("one", "household_emissions_factor"), 1.0)
        self.assertGreater(change("three", "ev_share"), 0.05)          # the ban two years earlier
        self.assertLess(after("three", "household_emissions_factor"), 1.0)
        self.assertGreater(after("two", "homes_insulated"), 350000)    # insulation
        self.assertLess(after("two", "household_emissions_factor"), 1.0)
        self.assertGreater(after("two", "energy_bills_saved"), 0)

    def test_education(self):
        self.assertLess(change("two", "fee_paying_students_now"), 0)   # a higher fee cap
        self.assertGreater(change("one", "school_attainment"), 0)      # free meals on Universal Credit

    def test_housing(self):
        self.assertGreater(change("one", "homes_built"), 5000)         # planning one step liberal
        self.assertGreater(change("one", "dwellings"), 0)
        self.assertGreater(change("two", "homes_built"), 4000)         # social housing, £2bn a year
        self.assertLess(change("three", "homes_built"), 0)             # strict rent controls

    def test_migration(self):
        self.assertLess(change("one", "net_migration_annual"), -20000)  # threshold at £50,000
        self.assertLess(change("one", "labour_force"), 0)
        self.assertLess(change("one", "population_total"), 0)

    def test_the_effects_build_over_time(self):
        """Policies act with inertia: the prison population, homes built and the electric
        cars on the road are further from 2024's after a year than after three months."""
        rows, base = run("one")[1], run("base")[1]
        for column in ("prison_population", "homes_built", "ev_fleet_extra", "smoking_prevalence"):
            early, year = rows[2][column] - base[2][column], rows[-1][column] - base[-1][column]
            self.assertGreater(abs(year), abs(early), column)
            self.assertGreater(year * early, 0.0, column)


class Reactions(unittest.TestCase):
    """Who likes and dislikes each policy for itself: its standing, by group."""

    CASES = {
        "standing_sentencing": ("one", {"pensioners": 1, "young": -1}),
        "standing_tobacco_duty": ("one", {"smokers": -1}),
        "standing_ev_grant": ("one", {"young": 1, "motorists": 1}),
        "standing_planning": ("one", {"home_owners": -1, "renters": 1}),
        "standing_school_meals": ("one", {"parents": 1, "lone_parents": 1}),
        "standing_winter_fuel": ("one", {"pensioners": 1}),
        "standing_visa_threshold": ("one", {"pensioners": 1, "young": -1}),
        "standing_prescription_charge": ("one", {"midlife": -1, "low_income": -1}),
        "standing_drinking_age": ("two", {"young": -1, "drinkers": -1}),
        "standing_fuel_duty": ("two", {"motorists": -1}),
        "standing_insulation": ("two", {"low_income": 1, "young": 1}),
        "standing_tuition": ("two", {"young": -1, "parents": -1}),
        "standing_social_housing": ("two", {"renters": 1, "low_income": 1}),
        "standing_bus_fare_cap": ("two", {"low_income": 1, "young": 1}),
        "standing_sugar_levy": ("two", {"low_income": -1}),
        "standing_alcohol_duty": ("three", {"drinkers": -1}),
        "standing_cannabis": ("three", {"young": 1, "pensioners": -1}),
        "standing_rent_controls": ("three", {"renters": 1}),  # owners: see test_reactions_reach_the_groups_approval
        "standing_petrol_ban": ("three", {"motorists": -1, "young": 1}),
    }

    def test_each_policy_goes_down_well_or_badly_with_the_groups_named(self):
        for name, (which, signs) in self.CASES.items():
            sim, _ = run(which)
            voters, member, standing = sim.column("voters"), sim.column("group_member"), sim.column(name)
            for key, sign in signs.items():
                g = GROUPS.index(key)
                weights = [voters[t] * member[t * len(GROUPS) + g] for t in range(len(voters))]
                mean = sum(w * s for w, s in zip(weights, standing)) / sum(weights)
                self.assertGreater(sign * mean, 0.0, f"{name}: {key}")

    def test_reactions_reach_the_groups_approval(self):
        self.assertGreater(change("one", "approval_pensioners"), 0)   # winter fuel, sentencing, visas
        self.assertLess(change("two", "approval_motorists"), 0)       # fuel duty
        self.assertGreater(change("three", "approval_renters"), change("three", "approval_home_owners"))

    def test_a_policy_moves_the_national_rating_by_tenths_of_a_point(self):
        for name in ("one", "two", "three"):
            self.assertLess(abs(change(name, "government_support")), 0.03, name)


class Extremes(unittest.TestCase):
    """Every policy at either end of its range for five years: the accounts hold every month
    (the oracle checks them), the levers stay put, and the indicators stay in bounds."""

    def test_nothing_explodes(self):
        for end in (0, 1):
            sim, rows = extreme(end)
            self.assertEqual(len(rows), FIVE_YEARS)
            for name, spec in LEVERS.items():
                expected = spec["range"][end]
                value = rows[-1][name]
                if spec["type"] == "money":
                    expected = round(expected * 100)
                self.assertEqual(value, expected, name)
            for row in rows:
                for column, value in row.items():
                    if isinstance(value, float):
                        self.assertTrue(math.isfinite(value), f"{end}: {column}")
                self.assertGreater(row["crime_incidents"], 4e6)
                self.assertLess(row["crime_incidents"], 15e6)
                self.assertTrue(0.0 < row["smoking_prevalence"] < 0.2)
                self.assertTrue(55.0 < row["healthy_life_expectancy"] < 65.0)
                self.assertTrue(0.3 < row["school_attainment"] < 0.6)
                self.assertTrue(100000 < row["homes_built"] < 400000)
                self.assertTrue(500000 < row["net_migration_annual"] < 900000)
                self.assertTrue(0.0 <= row["ev_share"] <= 1.0)
                self.assertTrue(0.5 < row["household_emissions_factor"] <= 1.1)
                self.assertTrue(0.0 < row["government_support"] < 1.0)


if __name__ == "__main__":
    unittest.main()
