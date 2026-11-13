"""Every line of conformance/cases.tsv must still be what the oracle computes.

The engine's tests check the same file, so this is what keeps the two tied together.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "oracle"))
sys.path.insert(0, str(ROOT / "tools"))

import gen_conformance  # noqa: E402


class Conformance(unittest.TestCase):
    def test_the_oracle_reproduces_every_recorded_case(self):
        sim = gen_conformance.warmed_up_simulation()
        lines = (ROOT / "conformance" / "cases.tsv").read_text(encoding="utf-8").split("\n")
        self.assertEqual(lines.pop(), "")
        self.assertGreater(len(lines), 3000)
        for number, line in enumerate(lines, start=1):
            ctx, typ, unit, formula, want = line.split("\t")
            got = gen_conformance.expected(sim, ctx, typ, unit, formula)
            self.assertEqual(got, want, f"line {number}: {formula!r}")


if __name__ == "__main__":
    unittest.main()
