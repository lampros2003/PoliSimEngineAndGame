"""Mods (docs/spec/07-mods.md, stage S7.1): the shared cases in conformance/mod_cases.toml,
which the engine runs too (crates/core/tests/mods.rs)."""

from __future__ import annotations

import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from polisim_oracle import FormulaError, ModelError, SimError, Simulation, load_model  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CASES = tomllib.loads((ROOT / "conformance" / "mod_cases.toml").read_text(encoding="utf-8"))


def text(value: str) -> str:
    return value.replace("\\n", "\n")


def outcome(case: dict):
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        (root / "model").mkdir()
        (root / "model" / "model.toml").write_text(CASES["base"], encoding="utf-8", newline="\n")
        mods = []
        for i, mod in enumerate(case.get("mods", [])):
            where = root / f"mod{i}"
            where.mkdir()
            (where / "mod.toml").write_text(text(mod["toml"]), encoding="utf-8", newline="\n")
            for name, content in mod.get("files", {}).items():
                (where / name).write_text(text(content), encoding="utf-8", newline="\n")
            mods.append(where)
        try:
            model = load_model(root / "model", mods)
            sim = Simulation(model)
            row = sim.step()
        except (ModelError, FormulaError, SimError, KeyError, TypeError) as exc:
            return "refused", exc, None
        return "ran", (model, row), sim


class SharedCases(unittest.TestCase):
    def test_every_case(self):
        self.assertGreaterEqual(len(CASES["case"]), 15)
        for case in CASES["case"]:
            with self.subTest(case["name"]):
                kind, detail, sim = outcome(case)
                self.assertEqual(kind, case["expect"], detail)
                if kind != "ran":
                    continue
                model, row = detail
                for name, value in case["values"].items():
                    got = row[name] if name in row else sim.rt.S[name]
                    self.assertEqual(got, value, name)
                self.assertEqual(len(model.mod_notes), case["notes"])
                self.assertEqual(model.model_hash, case["model_hash"])

    def test_mods_are_recorded_in_order(self):
        case = next(c for c in CASES["case"] if c["name"].startswith("two mods"))
        _, (model, _), _ = outcome(case)
        self.assertEqual([m.id for m in model.mods], ["first", "second"])


if __name__ == "__main__":
    if sys.argv[1:] == ["--hashes"]:
        # Prints each ran case's model hash, for filling in the case file.
        for case in CASES["case"]:
            kind, detail, _ = outcome(case)
            if kind == "ran":
                print(case["name"], detail[0].model_hash)
            else:
                print(case["name"], "refused:", detail)
    else:
        unittest.main()


class ExampleMod(unittest.TestCase):
    """mods/wealth_tax on the United Kingdom (models/uk/scenarios/wealth_tax.toml): a 1% tax
    on households' savings above a threshold."""

    def test_the_wealth_tax_is_a_receipt_and_costs_the_government_votes(self):
        from polisim_oracle.model import load_scenario
        from polisim_oracle.sim import from_scenario
        uk = ROOT / "models" / "uk" / "scenarios"
        taxed = from_scenario(load_scenario(uk / "wealth_tax.toml"))
        base = from_scenario(load_scenario(uk / "2025.toml"))
        row, before = taxed.step(), base.step()
        self.assertEqual([m.id for m in taxed.model.mods], ["wealth_tax"])
        # 1% a year on 40% of £1.9tn of deposits: about £630m a month (in pence).
        self.assertAlmostEqual(row["wealth_tax_paid"] / 100 / 633e6, 1.0, delta=0.01)
        parts = ["income_tax", "national_insurance", "council_tax", "vat", "production_taxes", "corporation_tax",
                 "other_receipts", "customs_duties", "wealth_tax_paid"]
        self.assertEqual(row["public_receipts"], sum(row[p] for p in parts))
        self.assertLess(row["government_support"], before["government_support"])
