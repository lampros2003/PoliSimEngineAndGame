"""The synthetic households (docs/S4-PLAN.md, milestone S4.1): models/uk/households/,
built by tools/uk/households.py from published tables. The weighted records must match the
published totals they were calibrated to."""

from __future__ import annotations

import csv
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
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


if __name__ == "__main__":
    unittest.main()


class Rules(unittest.TestCase):
    """The 2024-25 tax and benefit rules on the households (milestone S4.2)."""

    @classmethod
    def setUpClass(cls):
        import sys
        sys.path.insert(0, str(ROOT / "oracle"))
        from polisim_oracle import Simulation, load_model
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
