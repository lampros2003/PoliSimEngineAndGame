"""Weights that change (docs/spec/06-model-format-1.md, stage S4.4): the shared cases in
conformance/rake_cases.toml, which the engine runs too, and the test model models/raking."""

from __future__ import annotations

import csv
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from polisim_oracle import FormulaError, ModelError, SimError, Simulation, load_model  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CASES = tomllib.loads((ROOT / "conformance" / "rake_cases.toml").read_text(encoding="utf-8"))


def outcome(case: dict):
    """("refused" | "runtime" | "weights", the weights after step 0 or the error)."""
    text = CASES["base"]
    for old, new in case.get("replace", []):
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
            sim = Simulation(load_model(root))
        except (ModelError, FormulaError, SimError, KeyError, TypeError) as exc:
            return "refused", exc
        try:
            sim.step()
        except SimError as exc:
            return "runtime", exc
        return "weights", sim.column("w")


class SharedCases(unittest.TestCase):
    def test_every_case(self):
        for case in CASES["case"]:
            with self.subTest(case["name"]):
                kind, detail = outcome(case)
                self.assertEqual(kind, case["expect"], detail)
                if kind == "weights":
                    self.assertEqual(detail, case["weights"])


class TestModel(unittest.TestCase):
    """models/raking: three margins raked once a year."""

    @classmethod
    def setUpClass(cls):
        cls.model = load_model(ROOT / "models" / "raking")
        cls.rows = Simulation(cls.model, seed=1).run(25)

    def test_matches_the_recorded_hashes(self):
        with open(ROOT / "models" / "raking" / "golden" / "base.hashes.csv", newline="", encoding="utf-8") as handle:
            golden = [row["hash"] for row in csv.DictReader(handle)]
        self.assertEqual([row["hash"] for row in self.rows], golden[:25])

    def test_weights_change_only_when_raked(self):
        changed = [row["step"] for row in self.rows if row["weight_change"] != 0]
        self.assertEqual(changed, [0, 12, 24])

    def test_formulas_before_the_rake_see_the_old_weights(self):
        first = self.rows[0]
        self.assertNotEqual(first["households_before"], first["households"])
        self.assertEqual(self.rows[1]["households_before"], first["households"])

    def test_the_last_margin_is_met_to_within_rounding(self):
        # Six cells; each weight is rounded, so a cell can be off by half a household per record.
        for row in (self.rows[0], self.rows[12], self.rows[24]):
            self.assertLess(row["size_gap"], 40)

    def test_without_raking_the_weights_stay(self):
        rows = Simulation(self.model, seed=1, levers={"align": False}).run(13)
        self.assertTrue(all(row["weight_change"] == 0 for row in rows[1:]))
        self.assertEqual(rows[0]["households"], rows[0]["households_before"])

    def test_two_runs_of_one_model_keep_their_own_weights(self):
        one = Simulation(self.model, seed=1, levers={"align": False})
        two = Simulation(self.model, seed=1)
        two.step()
        self.assertEqual(one.step()["households"], self.rows[0]["households_before"])


if __name__ == "__main__":
    unittest.main()
