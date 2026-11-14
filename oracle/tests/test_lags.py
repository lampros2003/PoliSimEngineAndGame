"""Lags (docs/spec/06-model-format-1.md, stage S10.5): the shared cases in
conformance/lag_cases.toml, which the engine runs too, and what the loader makes."""

from __future__ import annotations

import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from polisim_oracle import FormulaError, ModelError, SimError, Simulation, load_model  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CASES = tomllib.loads((ROOT / "conformance" / "lag_cases.toml").read_text(encoding="utf-8"))
REFUSED = (ModelError, FormulaError, SimError, KeyError, TypeError)


def write(folder: Path, add: str) -> Path:
    (folder / "model.toml").write_text(CASES["base"] + "\n" + add.replace("\\n", "\n") + "\n",
                                       encoding="utf-8", newline="\n")
    return folder


def outcome(case: dict):
    """("refused", error), ("runtime", step, error) or ("ran", rows)."""
    commands: dict[int, dict] = {}
    for step, name, value in case.get("commands", []):
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
        self.assertGreaterEqual(len(CASES["case"]), 25)
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
    ADD = '[lag.back]\nlabel = "Back"\ndoc = "Three months ago"\nof = "cells"\nsteps = 3\ninitial = 0.0'

    def test_a_lag_is_a_chain_of_states_and_a_var_in_the_first_phase(self):
        with tempfile.TemporaryDirectory() as folder:
            model = load_model(write(Path(folder), self.ADD))
        made = sorted(n for n, d in model.symbols.items() if d.spec.get("lag") == "back")
        self.assertEqual(made, ["back", "back__1", "back__2", "back__3"])
        var = model.symbols["back"]
        self.assertEqual((var.kind, var.type, var.unit, var.dims, var.spec["phase"], var.spec["expr"]),
                         ("var", "real", model.symbols["cells"].unit, model.symbols["cells"].dims, "one", "back__3"))
        self.assertEqual((var.spec["label"], var.spec["doc"]), ("Back", "Three months ago"))
        for k, source in ((1, "cells"), (2, "back__1"), (3, "back__2")):
            state = model.symbols[f"back__{k}"]
            self.assertEqual((state.kind, state.spec["phase"], state.spec["next"]), ("state", "two", source))
            self.assertNotIn("label", state.spec)
        self.assertNotIn("lag", model.symbols["cells"].spec)

    def test_a_mod_may_add_a_lag(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "model").mkdir()
            write(root / "model", "")
            (root / "extra").mkdir()
            (root / "extra" / "mod.toml").write_text(
                '[mod]\nid = "extra"\nfiles = ["lags.toml"]\n', encoding="utf-8", newline="\n")
            (root / "extra" / "lags.toml").write_text(
                '[lag.extra_back]\nof = "count"\nsteps = 2\n', encoding="utf-8", newline="\n")
            sim = Simulation(load_model(root / "model", [root / "extra"]))
            self.assertEqual([sim.step()["extra_back"] for _ in range(4)], [0, 0, 1, 2])


if __name__ == "__main__":
    unittest.main()
