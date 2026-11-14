"""Bills (docs/spec/06-model-format-1.md, stage S5.4): the shared cases in
conformance/bill_cases.toml, which the engine runs too, and the UK model's coalition."""

from __future__ import annotations

import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from polisim_oracle import FormulaError, ModelError, SimError, Simulation, load_model  # noqa: E402
from polisim_oracle.model import load_scenario  # noqa: E402
from polisim_oracle.sim import from_scenario  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CASES = tomllib.loads((ROOT / "conformance" / "bill_cases.toml").read_text(encoding="utf-8"))


def outcome(case: dict):
    text = CASES["base"]
    for old, new in (CASES["capital"] if case.get("capital") else []) + case.get("replace", []):
        old, new = old.replace("\\n", "\n"), new.replace("\\n", "\n")
        assert text.count(old) == 1, (case["name"], old)
        text = text.replace(old, new)
    files = dict(CASES["files"], **case.get("files", {}))
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        (root / "model.toml").write_text(text, encoding="utf-8")
        for name, content in files.items():
            (root / name).write_text(content, encoding="utf-8")
        try:
            sim = Simulation(load_model(root), commands={0: dict(case.get("set", {}))})
        except (ModelError, FormulaError, SimError, KeyError, TypeError) as exc:
            return "refused", exc
        try:
            sim.step()
        except (SimError, ModelError) as exc:
            return "runtime", exc
        return "ran", sim


class SharedCases(unittest.TestCase):
    def test_every_case(self):
        for case in CASES["case"]:
            with self.subTest(case["name"]):
                kind, detail = outcome(case)
                self.assertEqual(kind, case["expect"], detail)
                if kind == "ran":
                    for lever, value in case["levers"].items():
                        self.assertEqual(detail.rt.S[lever], value, lever)
                    # Stage S12.4: an expected vote may also give its cost and whether it was refused.
                    got = [[v["lever"], v["for"], v["passed"], v["cost"], v["refused"]][:len(want)]
                           for v, want in zip(detail.votes, case["votes"])]
                    self.assertEqual(len(detail.votes), len(case["votes"]))
                    self.assertEqual(got, case["votes"])


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
