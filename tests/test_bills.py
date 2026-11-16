"""Bills (docs/spec/06-model-format-1.md, stage S5.4) on the UK model. The shared cases in
conformance/bill_cases.toml are run by crates/core/tests/bills.rs."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from engine import Simulation, from_scenario, load_model, load_scenario  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


class UnitedKingdom(unittest.TestCase):
    def test_a_coalition_loses_the_bills_its_partner_opposes(self):
        sim = from_scenario(load_scenario(ROOT / "models" / "uk" / "scenarios" / "coalition_bill.toml"))
        rows = sim.run(3)
        self.assertEqual([(v["lever"], v["for"], v["passed"]) for v in sim.votes],
                         [("basic_rate", 283, False), ("personal_allowance", 283, False), ("vat_rate", 627, True)])
        self.assertEqual([r["bills_defeated"] for r in rows], [0, 0, 2])
        self.assertEqual((rows[-1]["basic_rate"], rows[-1]["vat_rate"]), (0.2, 0.21))

    def test_the_players_minority_coalition_loses_a_move_to_the_left(self):
        path = ROOT / "models" / "uk" / "scenarios" / "hung_parliament.toml"
        scenario = load_scenario(path)
        sim = Simulation(scenario.model, scenario.seed, scenario.preset, scenario.params,
                         commands={2: {"basic_rate": 0.21, "personal_allowance": 13000}})
        rows = sim.run(3)
        self.assertTrue(rows[-1]["player_governs"])
        self.assertEqual([(v["lever"], v["for"], v["passed"]) for v in sim.votes],
                         [("basic_rate", 324, False), ("personal_allowance", 620, True)])

    def test_the_majority_government_passes_its_bills(self):
        sim = Simulation(load_model(ROOT / "models" / "uk"), seed=2025, commands={0: {"basic_rate": 0.18}})
        row = sim.step()
        self.assertEqual(row["basic_rate"], 0.18)
        # A move to the right: the leader and every bloc to its right.
        self.assertEqual(sim.votes[0]["for"], 650 - 4 - 9 - 4)


if __name__ == "__main__":
    unittest.main()
