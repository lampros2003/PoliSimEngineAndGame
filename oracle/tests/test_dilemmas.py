"""Dilemmas (docs/spec/06-model-format-1.md, stage S9.1): the shared cases in
conformance/dilemma_cases.toml, which the engine runs too, and what the loader keeps."""

from __future__ import annotations

import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from polisim_oracle import FormulaError, ModelError, SimError, Simulation, load_model  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CASES = tomllib.loads((ROOT / "conformance" / "dilemma_cases.toml").read_text(encoding="utf-8"))
REFUSED = (ModelError, FormulaError, SimError, KeyError, TypeError)


def write(folder: Path, add: str) -> Path:
    (folder / "model.toml").write_text(CASES["base"] + "\n" + add.replace("\\n", "\n") + "\n",
                                       encoding="utf-8", newline="\n")
    return folder


def outcome(case: dict):
    """("refused", error), ("runtime", step, error) or ("ran", rows)."""
    commands: dict[int, dict] = {}
    for step, name, value in case.get("answers", []):
        commands.setdefault(step, {})[name] = value
    with tempfile.TemporaryDirectory() as folder:
        try:
            sim = Simulation(load_model(write(Path(folder), case["add"])), commands=commands)
        except REFUSED as exc:
            return ("refused", exc)
        rows = []
        for step in range(case["steps"]):
            try:
                rows.append(sim.step())
            except SimError as exc:
                return ("runtime", step, exc)
        return ("ran", rows)


class SharedCases(unittest.TestCase):
    def test_every_case(self):
        self.assertGreaterEqual(len(CASES["case"]), 30)
        for case in CASES["case"]:
            with self.subTest(case["name"]):
                got = outcome(case)
                self.assertEqual(got[0], case["expect"], got[1:])
                if got[0] == "ran":
                    for name, values in case["series"].items():
                        self.assertEqual([row[name] for row in got[1]], values, name)
                if got[0] == "runtime":
                    self.assertEqual(got[1], case["at"], got[2])


class Loader(unittest.TestCase):
    ADD = ('[dilemma.d]\nlabel = "D"\ndoc = "A question"\nstart = "count >= 2"\nagain_after = 12\n'
           '[[dilemma.d.option]]\nname = "a"\nlabel = "Yes"\nmonths = 3\n'
           '[[dilemma.d.option]]\nname = "b"\ndoc = "No"')

    def test_the_model_keeps_each_dilemma_and_marks_what_it_makes(self):
        with tempfile.TemporaryDirectory() as folder:
            model = load_model(write(Path(folder), self.ADD))
        self.assertEqual(model.dilemmas, [{
            "name": "d", "label": "D", "doc": "A question", "again_after": 12,
            "options": [{"name": "a", "label": "Yes", "doc": "", "months": 3},
                        {"name": "b", "label": "b", "doc": "No", "months": None}]}])
        made = sorted(n for n, d in model.symbols.items() if d.spec.get("dilemma") == "d")
        self.assertEqual(made, ["d", "d_age", "d_answer", "d_choice", "d_months", "d_open"])
        lever = model.symbols["d"]
        self.assertEqual((lever.kind, lever.type, lever.spec["range"], lever.spec["label"]), ("lever", "int", [0, 2], "D"))
        self.assertNotIn("leaning", lever.spec)

    def test_a_dilemma_cannot_be_answered_at_the_start(self):
        with tempfile.TemporaryDirectory() as folder:
            model = load_model(write(Path(folder), self.ADD))
        with self.assertRaises(ModelError):
            Simulation(model, levers={"d": 1})


if __name__ == "__main__":
    unittest.main()
