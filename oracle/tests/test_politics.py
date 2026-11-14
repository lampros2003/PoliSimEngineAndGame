"""The UK's voters (docs/S5-PLAN.md, milestone S5.2): models/uk/politics.toml, written by
tools/uk/voters.py from the households and the 2024 general election."""

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
REGIONS = ["north_east", "north_west", "yorkshire", "east_midlands", "west_midlands", "east", "london", "south_east",
           "south_west", "wales", "scotland", "northern_ireland"]
BLOCS = ["centre_left", "centre_right", "liberal", "populist_right", "green", "scottish_nationalist",
         "welsh_nationalist", "northern_ireland", "other"]
SEED = 2025


@functools.lru_cache(maxsize=None)
def model():
    return load_model(UK)


@functools.lru_cache(maxsize=None)
def first_month():
    sim = Simulation(model(), seed=SEED)
    row = sim.step()
    return sim, row


def run(steps: int, **levers) -> list[dict]:
    return Simulation(model(), seed=SEED, levers=levers).run(steps)


class BaseMonth(unittest.TestCase):
    def test_every_region_votes_as_in_2024(self):
        sim, _ = first_month()
        intention = sim.column("regional_intention")  # region by bloc
        votes = {r: [0] * len(BLOCS) for r in REGIONS}
        valid = dict.fromkeys(REGIONS, 0)
        with open(UK / "data" / "elections" / "ge2024.csv", newline="", encoding="utf-8") as handle:
            for s in csv.DictReader(handle):
                valid[s["region"]] += int(s["valid_votes"])
                for b, bloc in enumerate(BLOCS):
                    votes[s["region"]][b] += int(s[bloc])
        for r, region in enumerate(REGIONS):
            for b, bloc in enumerate(BLOCS):
                self.assertAlmostEqual(intention[r * len(BLOCS) + b], votes[region][b] / valid[region], places=6,
                                       msg=f"{region} {bloc}")

    def test_turnout_and_the_governments_share(self):
        _, row = first_month()
        self.assertAlmostEqual(row["turnout"], 28_809_340 / 48_224_212, delta=0.01)
        self.assertAlmostEqual(row["government_support"], 0.337, delta=0.005)

    def test_the_voters_are_the_households_adults(self):
        sim, _ = first_month()
        adults = 0
        with open(UK / "households" / "households.csv", newline="", encoding="utf-8") as handle:
            for r in csv.DictReader(handle):
                adults += int(r["weight"]) * sum(1 for i in range(1, 5)
                                                 if int(r["adults"]) >= i and int(r[f"age{i}"]) >= 18)
        self.assertEqual(sum(sim.column("voters")), adults)


class Response(unittest.TestCase):
    def test_a_tax_rise_costs_the_government_support(self):
        base, higher = run(3), run(3, basic_rate=0.25)
        self.assertLess(higher[-1]["government_support"], base[-1]["government_support"] - 0.001)

    def test_a_higher_allowance_wins_it_support(self):
        base, kinder = run(3), run(3, personal_allowance=15000)
        self.assertGreater(kinder[-1]["government_support"], base[-1]["government_support"] + 0.001)

    def test_unchanged_policy_wears_the_government_down(self):
        rows = run(13)
        self.assertLess(rows[-1]["government_support"], rows[0]["government_support"])
        self.assertGreater(rows[-1]["government_support"], rows[0]["government_support"] - 0.03)


if __name__ == "__main__":
    unittest.main()
