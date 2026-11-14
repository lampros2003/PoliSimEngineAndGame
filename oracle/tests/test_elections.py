"""The 2024 general election and the census by constituency (docs/S5-PLAN.md, milestone
S5.0): models/uk/data/elections/, extracted by tools/uk/elections.py."""

from __future__ import annotations

import csv
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "models" / "uk" / "data" / "elections"
BLOCS = ["centre_left", "centre_right", "liberal", "populist_right", "green", "scottish_nationalist",
         "welsh_nationalist", "northern_ireland", "other"]


def rows(name: str) -> list[dict]:
    with open(DATA / name, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


class Results(unittest.TestCase):
    def test_650_seats_as_declared(self):
        seats = rows("ge2024.csv")
        self.assertEqual(len(seats), 650)
        won = {b: sum(1 for s in seats if s["winner"] == b) for b in BLOCS}
        # Labour 411, Conservative 121, Liberal Democrat 72, Reform UK 5, Green 4, SNP 9,
        # Plaid Cymru 4, Northern Ireland's 18, and 6 others (5 independents and the Speaker).
        self.assertEqual(won, {"centre_left": 411, "centre_right": 121, "liberal": 72, "populist_right": 5, "green": 4,
                               "scottish_nationalist": 9, "welsh_nationalist": 4, "northern_ireland": 18, "other": 6})

    def test_votes_add_up_in_every_constituency(self):
        for s in rows("ge2024.csv"):
            votes = [int(s[b]) for b in BLOCS]
            self.assertEqual(sum(votes), int(s["valid_votes"]), s["name"])
            # First past the post counts candidates: "other" by its best-placed candidate.
            contest = votes[:-1] + [int(s["other_best"])]
            self.assertEqual(BLOCS[contest.index(max(contest))], s["winner"], s["name"])
            self.assertLessEqual(int(s["valid_votes"]), int(s["electorate"]))

    def test_national_shares(self):
        seats = rows("ge2024.csv")
        valid = sum(int(s["valid_votes"]) for s in seats)
        self.assertEqual(valid, 28_809_340)
        self.assertAlmostEqual(sum(int(s["centre_left"]) for s in seats) / valid, 0.337, places=3)
        self.assertAlmostEqual(sum(int(s["populist_right"]) for s in seats) / valid, 0.143, places=3)


class Census(unittest.TestCase):
    def test_every_england_and_wales_constituency(self):
        census = {r["code"] for r in rows("census_pcon.csv")}
        results = {s["code"] for s in rows("ge2024.csv") if s["code"][0] in "EW"}
        self.assertEqual(census, results)
        self.assertEqual(len(census), 575)


if __name__ == "__main__":
    unittest.main()
