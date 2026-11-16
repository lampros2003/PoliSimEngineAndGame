"""The synthetic households (docs/S4-PLAN.md, milestone S4.1): models/uk/households/,
built by tools/uk/households.py from published tables. The weighted records must match the
published totals they were calibrated to."""

from __future__ import annotations

import csv
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOUSEHOLDS = ROOT / "models" / "uk" / "households" / "households.csv"


def rows():
    with open(HOUSEHOLDS, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


class Households(unittest.TestCase):
    def test_twenty_thousand_records_with_whole_positive_weights(self):
        records = rows()
        self.assertEqual(len(records), 20_000)
        self.assertEqual(len({r["id"] for r in records}), 20_000)
        self.assertTrue(all(int(r["weight"]) >= 1 for r in records))

    def test_weighted_totals_match_the_published_figures(self):
        records = rows()
        weight = [int(r["weight"]) for r in records]
        households = sum(weight)
        people = sum(w * (int(r["adults"]) + int(r["children"])) for w, r in zip(weight, records))
        workers = sum(w * sum(1 for i in range(1, 5) if float(r[f"earnings{i}"]) > 0) for w, r in zip(weight, records))
        with open(ROOT / "models" / "uk" / "data" / "annual.csv", newline="", encoding="utf-8") as handle:
            employment = float(next(r for r in csv.DictReader(handle) if r["period"] == "2024")["employment"]) * 1000
        self.assertLess(abs(households / 28_609_000 - 1), 0.001)  # Families and households 2024, table 7
        self.assertLess(abs(people / 67_361_000 - 1), 0.001)  # table 8: people in households
        self.assertLess(abs(workers / employment - 1), 0.001)

    def test_people_by_region_follow_the_population(self):
        records = rows()
        by_region = {}
        for r in records:
            by_region[r["region_code"]] = by_region.get(r["region_code"], 0) + int(r["weight"]) * (
                int(r["adults"]) + int(r["children"]))
        with open(ROOT / "models" / "uk" / "data" / "population.csv", newline="", encoding="utf-8") as handle:
            pop = list(csv.DictReader(handle))
        regions = list(dict.fromkeys(r["region"] for r in pop))
        total_pop = sum(int(r["people"]) for r in pop)
        total_hh = sum(by_region.values())
        for code, region in enumerate(regions):
            share_pop = sum(int(r["people"]) for r in pop if r["region"] == region) / total_pop
            share_hh = by_region[str(code)] / total_hh
            self.assertLess(abs(share_hh / share_pop - 1), 0.02, region)


class Employment(unittest.TestCase):
    def test_people_in_work_by_region_follow_the_survey(self):
        # Stage S6.2: each region's share of people in work is the Annual Population Survey's.
        workers = {}
        for r in rows():
            n = sum(1 for i in range(1, 5) if float(r[f"earnings{i}"]) > 0)
            workers[int(r["region_code"])] = workers.get(int(r["region_code"]), 0) + int(r["weight"]) * n
        with open(ROOT / "models" / "uk" / "data" / "labour_regions.csv", newline="", encoding="utf-8") as handle:
            survey = [int(r["employed"]) for r in csv.DictReader(handle)]
        for code, employed in enumerate(survey):
            self.assertLess(abs(workers[code] / sum(workers.values()) / (employed / sum(survey)) - 1), 0.001, code)


class Rules(unittest.TestCase):
    """The 2024-25 tax and benefit rules on the households (milestone S4.2)."""

    @classmethod
    def setUpClass(cls):
        import sys
        sys.path.insert(0, str(ROOT / "tools"))
        from engine import Simulation, load_model
        cls.Simulation = Simulation
        cls.model = load_model(ROOT / "models" / "uk" / "households")
        cls.first = Simulation(cls.model, seed=1).step()

    def test_national_insurance_is_within_five_percent_of_the_published_total(self):
        with open(ROOT / "models" / "uk" / "data" / "annual.csv", newline="", encoding="utf-8") as handle:
            published = float(next(r for r in csv.DictReader(handle) if r["period"] == "2024")["social_contributions"])
        modelled = (self.first["employee_ni_total"] + self.first["employer_ni_total"]) * 12 / 1e8
        self.assertLess(abs(modelled / published - 1), 0.05)

    def test_income_tax_by_region_adds_up(self):
        sim = self.Simulation(self.model, seed=1)
        row = sim.step()
        by_region = sum(sim.rt.C["income_tax_by_region"])
        self.assertAlmostEqual(by_region / (row["income_tax_total"]), 1.0, places=6)

    def test_a_higher_personal_allowance_lowers_income_tax(self):
        richer = self.Simulation(self.model, seed=1, levers={"personal_allowance": 15000}).step()
        self.assertLess(richer["income_tax_total"], self.first["income_tax_total"])
        # Roughly £2,430 more allowance at 20% for some 30 million taxpayers: £10bn to £20bn a year.
        saved = (self.first["income_tax_total"] - richer["income_tax_total"]) * 12 / 1e11
        self.assertTrue(10 < saved < 20, saved)

    def test_a_lower_universal_credit_taper_costs_money(self):
        gentler = self.Simulation(self.model, seed=1, levers={"uc_taper": 0.45}).step()
        self.assertGreater(gentler["universal_credit_total"], self.first["universal_credit_total"])


class Breakdowns(unittest.TestCase):
    """Who gains, who loses (milestone S4.5): net income per household by income decile,
    household type and region, which must add up to the national figures."""

    @classmethod
    def setUpClass(cls):
        import sys
        sys.path.insert(0, str(ROOT / "tools"))
        from engine import Simulation, load_model
        cls.Simulation = Simulation
        cls.model = load_model(ROOT / "models" / "uk" / "households")
        cls.sim = Simulation(cls.model, seed=1)
        cls.row = cls.sim.step()
        cls.records = rows()

    def weights_by(self, key: str, size: int, first: int = 0) -> list[int]:
        out = [0] * size
        for r in self.records:
            out[int(r[key]) - first] += int(r["weight"])
        return out

    def test_each_decile_holds_a_tenth_of_households(self):
        weights = self.weights_by("income_decile", 10, first=1)
        for w in weights:
            self.assertLess(abs(w / (sum(weights) / 10) - 1), 0.01)

    def test_the_groups_add_up_to_the_national_figures(self):
        net = self.sim.column("net_income")
        weight = [int(r["weight"]) for r in self.records]
        total = sum(w * v for w, v in zip(weight, net))
        self.assertAlmostEqual(self.row["net_income_average"] * sum(weight) / total, 1.0, places=9)
        for name, key, size, first in (("net_income_by_decile", "income_decile", 10, 1),
                                       ("net_income_by_household_type", "type", 10, 0),
                                       ("net_income_by_region", "region_code", 12, 0)):
            means, weights = self.sim.column(name), self.weights_by(key, size, first)
            self.assertEqual(len(means), size)
            self.assertAlmostEqual(sum(m * w for m, w in zip(means, weights)) / total, 1.0, places=9, msg=name)

    def test_net_income_rises_with_the_decile(self):
        means = self.sim.column("net_income_by_decile")
        self.assertEqual(means, sorted(means))
        # About £10,000 a year in the poorest tenth and £105,000 in the richest (pence a month).
        self.assertTrue(9_000 < means[0] * 12 / 100 < 12_000, means[0])
        self.assertTrue(90_000 < means[-1] * 12 / 100 < 120_000, means[-1])

    def test_a_basic_rate_rise_takes_most_from_the_upper_deciles(self):
        sim = self.Simulation(self.model, seed=1, levers={"basic_rate": 0.21})
        sim.step()
        change = [a - b for a, b in zip(sim.column("net_income_by_decile"), self.sim.column("net_income_by_decile"))]
        self.assertTrue(all(c <= 0 for c in change), change)
        self.assertLess(change[8], change[0])
        regions = [a - b for a, b in zip(sim.column("net_income_by_region"), self.sim.column("net_income_by_region"))]
        self.assertEqual(regions[10], 0.0)  # Scotland sets its own rates
        self.assertTrue(all(c < 0 for i, c in enumerate(regions) if i != 10), regions)


if __name__ == "__main__":
    unittest.main()
