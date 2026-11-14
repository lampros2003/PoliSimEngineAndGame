"""Situations (docs/spec/06-model-format-1.md, stage S7.3): the shared cases in
conformance/situation_cases.toml, which the engine runs too, and the UK's own."""

from __future__ import annotations

import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from polisim_oracle import FormulaError, ModelError, SimError, Simulation, load_model  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CASES = tomllib.loads((ROOT / "conformance" / "situation_cases.toml").read_text(encoding="utf-8"))


def outcome(case: dict):
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        (root / "model.toml").write_text(CASES["base"] + "\n" + case["add"].replace("\\n", "\n") + "\n",
                                         encoding="utf-8", newline="\n")
        try:
            sim = Simulation(load_model(root))
            rows = [sim.step() for _ in range(case["steps"])]
        except (ModelError, FormulaError, SimError, KeyError, TypeError) as exc:
            return "refused", exc
        return "ran", rows


class SharedCases(unittest.TestCase):
    def test_every_case(self):
        self.assertGreaterEqual(len(CASES["case"]), 10)
        for case in CASES["case"]:
            with self.subTest(case["name"]):
                kind, detail = outcome(case)
                self.assertEqual(kind, case["expect"], detail)
                if kind == "ran":
                    for name, values in case["series"].items():
                        self.assertEqual([row[name] for row in detail], values, name)


if __name__ == "__main__":
    unittest.main()


class UnitedKingdom(unittest.TestCase):
    """The UK's situations (models/uk/situations.toml)."""

    def test_a_quiet_start_then_a_recession_when_purchases_are_cut(self):
        from polisim_oracle.model import load_scenario
        from polisim_oracle.sim import from_scenario
        scenario = load_scenario(ROOT / "models" / "uk" / "scenarios" / "2025.toml")
        names = [d.name for d in scenario.model.symbols.values() if d.spec.get("situation")]
        self.assertEqual(names, ["recession", "strong_growth", "high_unemployment", "high_inflation",
                                 "debt_above_output", "budget_surplus", "no_majority"])
        scenario.commands = {1: {"procurement_bill": 20_000_000_000}}
        sim = from_scenario(scenario)
        first = sim.step()
        self.assertEqual([n for n in names if first[n]], [])
        second = sim.step()
        self.assertTrue(second["recession"])
        self.assertLess(second["output_growth"], -0.005)
