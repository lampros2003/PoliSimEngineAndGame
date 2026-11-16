"""Situations (docs/spec/06-model-format-1.md, stage S7.3): the UK's own. The shared cases
in conformance/situation_cases.toml are run by crates/core/tests/situations.rs."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from engine import from_scenario, load_scenario  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


class UnitedKingdom(unittest.TestCase):
    """The UK's situations (models/uk/situations.toml)."""

    def test_a_quiet_start_then_a_recession_when_public_services_are_cut(self):
        scenario = load_scenario(ROOT / "models" / "uk" / "scenarios" / "2025.toml")
        names = [d.name for d in scenario.model.symbols.values() if d.spec.get("situation")]
        self.assertEqual(names, ["recession", "strong_growth", "high_unemployment", "high_inflation",
                                 "debt_above_output", "budget_surplus", "no_majority", "health_strain",
                                 "schools_strain", "policing_strain", "services_improving", "emissions_above_path",
                                 "emissions_on_track", "waiting_list_record", "waiting_list_falling",
                                 # Stage S13.7: the indicators of stage S13.5.
                                 "crime_wave", "healthy_life_falling", "housing_shortage", "building_boom",
                                 "migration_high", "migration_falling",
                                 # Stage S13.8: the public finances.
                                 "lenders_confidence",
                                 # Stage S14.5: homelessness.
                                 "homelessness_rising",
                                 # Stage S15.2: strikes and rents.
                                 "strike_wave", "rents_soaring"])
        scenario.commands = {1: {d.name: d.spec["default"] * 3 // 4 for d in scenario.model.symbols.values()
                                 if d.kind == "lever" and d.name.startswith("spending_")}}
        sim = from_scenario(scenario)
        first = sim.step()
        self.assertEqual([n for n in names if first[n]], [])
        second = sim.step()
        self.assertTrue(second["recession"])
        self.assertLess(second["output_growth"], -0.005)


if __name__ == "__main__":
    unittest.main()
