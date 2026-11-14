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
