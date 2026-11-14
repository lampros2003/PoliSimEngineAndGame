"""Stage S10.7: the oracle still gives the hashes and errors recorded in
conformance/random_models.toml (tools/gen_random_models.py), which the engine must match
(crates/core/tests/random_models.rs)."""

from __future__ import annotations

import sys
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "oracle"))
sys.path.insert(0, str(ROOT / "tools"))

from gen_random_models import outcome  # noqa: E402

MODELS = tomllib.loads((ROOT / "conformance" / "random_models.toml").read_text(encoding="utf-8"))["model"]


class RandomModels(unittest.TestCase):
    def test_the_oracle_gives_the_recorded_hashes(self):
        self.assertGreaterEqual(len(MODELS), 80)
        stopped = 0
        for model in MODELS:
            with self.subTest(model["name"]):
                commands: dict[int, dict] = {}
                for step, lever, value in model["commands"]:
                    commands.setdefault(step, {})[lever] = value
                result = outcome(model["text"], model["records"], model["seed"], commands)
                self.assertIsNotNone(result, "the oracle refuses it")
                hashes, error = result
                self.assertEqual(hashes, model["hashes"])
                self.assertEqual(error, (model["error_at"], model["error"]) if "error_at" in model else None)
                stopped += error is not None
        self.assertGreaterEqual(stopped, 5, "a few models should stop with an error")


if __name__ == "__main__":
    unittest.main()
