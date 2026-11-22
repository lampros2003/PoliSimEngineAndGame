"""Mods (docs/spec/07-mods.md, stage S7.1): the order mods are kept in, and the example mod
on the UK. The shared cases in conformance/mod_cases.toml are run by
crates/core/tests/mods.rs."""

from __future__ import annotations

import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from engine import from_scenario, load_model, load_scenario  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CASES = tomllib.loads((ROOT / "conformance" / "mod_cases.toml").read_text(encoding="utf-8"))


def text(value: str) -> str:
    return value.replace("\\n", "\n")


class Order(unittest.TestCase):
    def test_mods_are_recorded_in_order(self):
        case = next(c for c in CASES["case"] if c["name"].startswith("two mods"))
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "model").mkdir()
            (root / "model" / "model.toml").write_text(CASES["base"], encoding="utf-8", newline="\n")
            mods = []
            for i, mod in enumerate(case["mods"]):
                where = root / f"mod{i}"
                where.mkdir()
                (where / "mod.toml").write_text(text(mod["toml"]), encoding="utf-8", newline="\n")
                for name, content in mod.get("files", {}).items():
                    (where / name).write_text(text(content), encoding="utf-8", newline="\n")
                mods.append(where)
            model = load_model(root / "model", mods)
            self.assertEqual([m.id for m in model.mods], ["first", "second"])


class ExampleMod(unittest.TestCase):
    """tests/mods/wealth_tax on the United Kingdom (models/uk/scenarios/wealth_tax.toml): a 1% tax
    on households' savings above a threshold."""

    def test_the_wealth_tax_is_a_receipt_and_costs_the_government_votes(self):
        uk = ROOT / "models" / "uk" / "scenarios"
        taxed = from_scenario(load_scenario(uk / "wealth_tax.toml"))
        base = from_scenario(load_scenario(uk / "2025.toml"))
        row, before = taxed.step(), base.step()
        self.assertEqual([m.id for m in taxed.model.mods], ["wealth_tax"])
        # 1% a year on 40% of £1.9tn of deposits: about £630m a month (in pence).
        self.assertAlmostEqual(row["wealth_tax_paid"] / 100 / 633e6, 1.0, delta=0.01)
        parts = ["income_tax", "national_insurance", "council_tax", "vat", "production_taxes", "corporation_tax",
                 "other_receipts", "customs_duties", "carbon_tax_firms", "carbon_tax_households", "wealth_tax_paid"]
        self.assertEqual(row["public_receipts"], sum(row[p] for p in parts))
        self.assertLess(row["government_support"], before["government_support"])


if __name__ == "__main__":
    unittest.main()
