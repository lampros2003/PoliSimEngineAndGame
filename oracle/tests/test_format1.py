"""Model format 1: dimensions (docs/spec/06-model-format-1.md), on models/cohort and on
small models written by the tests."""

from __future__ import annotations

import csv
import math
import shutil
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from polisim_oracle import FormulaError, ModelError, SimError, Simulation, load_model  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
COHORT = ROOT / "models" / "cohort"

HEAD = """
[model]
id = "t"
format = 1
currency = "GBP"
minor_units = 100
step = "month"
phases = ["one"]

[dim.age]
range = [10, 13]

[dim.sex]
members = ["female", "male"]
"""


def build(extra: str, files: dict[str, str] | None = None) -> Simulation:
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        (root / "model.toml").write_text(HEAD + textwrap.dedent(extra), encoding="utf-8")
        for name, text in (files or {}).items():
            (root / name).parent.mkdir(parents=True, exist_ok=True)
            (root / name).write_text(textwrap.dedent(text).lstrip(), encoding="utf-8")
        return Simulation(load_model(root))


class Loading(unittest.TestCase):
    def test_cells_are_placed_by_their_members_whatever_the_file_order(self):
        sim = Simulation(load_model(COHORT))
        m = sim.model
        with open(COHORT / "data" / "population.csv", newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        regions, sexes = m.dims["region"].members, m.dims["sex"].members
        for row in rows[:: 37]:
            flat = (regions.index(row["region"]) * 2 + sexes.index(row["sex"])) * 101 + int(row["age"])
            self.assertEqual(sim.rt.C["population"][flat], float(row["people"]))

    def test_a_parameter_can_take_a_column_per_preset(self):
        low = Simulation(load_model(COHORT), preset="low").rt.C["mortality"]
        high = Simulation(load_model(COHORT), preset="high").rt.C["mortality"]
        self.assertTrue(all(a < b for a, b in zip(low[1:], high[1:])))

    def test_a_single_value_fills_every_cell(self):
        sim = build("""
            [param.rate]
            type = "real"
            unit = "1"
            dims = ["sex", "age"]
            value = 0.5
        """)
        self.assertEqual(sim.rt.C["rate"], [0.5] * 8)

    def test_bad_declarations_are_refused(self):
        bad = {
            "dims in format 0": ("", {"format": 0}),
            "an unknown dimension": ('[var.x]\ntype = "real"\nunit = "1"\nphase = "one"\ndims = ["height"]\nexpr = "1.0"\n', {}),
            "a repeated dimension": ('[var.x]\ntype = "real"\nunit = "1"\nphase = "one"\ndims = ["age", "age"]\nexpr = "1.0"\n', {}),
            "a dimensioned lever": ('[lever.x]\ntype = "real"\nunit = "1"\ndefault = 1.0\ndims = ["age"]\n', {}),
            "a member named like an element": ('[param.female]\ntype = "real"\nunit = "1"\nvalue = 1.0\n', {}),
        }
        for what, (extra, change) in bad.items():
            with self.subTest(what):
                head = HEAD.replace("format = 1", f"format = {change.get('format', 1)}")
                if change.get("format") == 0:
                    extra = ""
                with tempfile.TemporaryDirectory() as folder:
                    (Path(folder) / "model.toml").write_text(head + extra, encoding="utf-8")
                    with self.assertRaises(ModelError):
                        load_model(folder)

    def test_a_data_file_must_hold_every_cell_once(self):
        param = """
            [param.rate]
            type = "real"
            unit = "1"
            dims = ["sex", "age"]
            data = "rates.csv"
        """
        full = "sex,age,value\n" + "".join(f"{s},{a},0.1\n" for s in ("female", "male") for a in range(10, 14))
        cases = {
            "missing": full.replace("male,13,0.1\n", ""),
            "repeated": full + "male,13,0.2\n",
            "unknown": full.replace("male,13", "male,14"),
            "no value column": full.replace("value", "rate"),
        }
        build(param, {"rates.csv": full})
        for what, text in cases.items():
            with self.subTest(what), self.assertRaises(ModelError):
                build(param, {"rates.csv": text})


class Scope(unittest.TestCase):
    def test_reading_a_dimension_out_of_scope_is_refused(self):
        refused = [
            '[var.total]\ntype = "real"\nunit = "1"\nphase = "one"\nexpr = "rate"',
            '[var.total]\ntype = "real"\nunit = "1"\nphase = "one"\nexpr = "sum(rate, age)"',
            '[var.x]\ntype = "real"\nunit = "1"\nphase = "one"\ndims = ["age"]\nexpr = "sum(rate, age, sex)"',
            '[var.x]\ntype = "int"\nunit = "1"\nphase = "one"\nexpr = "coord(age)"',
            '[var.x]\ntype = "real"\nunit = "1"\nphase = "one"\nexpr = "rate[age: 10, age: 11, sex: male]"',
            '[var.x]\ntype = "real"\nunit = "1"\nphase = "one"\ndims = ["age"]\nexpr = "cohort_shift(rate, sex)"',
            '[var.x]\ntype = "real"\nunit = "1"\nphase = "one"\ndims = ["sex", "age"]\nexpr = "rand(noise)"',
            '[var.x]\ntype = "real"\nunit = "1"\nphase = "one"\nexpr = "rate[age: 10.0, sex: male]"',
        ]
        base = """
            [stream.noise]
            [param.rate]
            type = "real"
            unit = "1"
            dims = ["sex", "age"]
            value = 0.5
        """
        for formula in refused:
            with self.subTest(formula), self.assertRaises(FormulaError):
                build(base + formula)


class Semantics(unittest.TestCase):
    BASE = """
        [param.rate]
        type = "real"
        unit = "1"
        dims = ["sex", "age"]
        data = "rates.csv"

        [param.count]
        type = "int"
        unit = "1"
        dims = ["sex", "age"]
        data = "rates.csv"
        column = "count"
    """
    FILES = {"rates.csv": "sex,age,value,count\n" + "".join(
        f"{s},{a},{(i * 4 + a - 10) / 10},{(i + 1) * a}\n" for i, s in enumerate(("female", "male")) for a in range(10, 14))}

    def sim(self, extra: str = "") -> Simulation:
        return build(self.BASE + extra, self.FILES)

    def test_sum_takes_terms_in_row_major_order_of_the_dimensions_listed(self):
        sim = self.sim()
        rates = sim.rt.C["rate"]  # stored sex-major: female 10..13, then male 10..13
        by_age_then_sex = [rates[s * 4 + a] for a in range(4) for s in range(2)]
        expected = 0.0
        for term in by_age_then_sex:
            expected = expected + term
        self.assertEqual(sim.evaluate("sum(rate, age, sex)"), expected)
        self.assertEqual(sim.evaluate("sum(count, sex, age)", type="int"), sum(sim.rt.C["count"]))

    def test_coord_gives_members_of_a_range_and_positions_of_a_list(self):
        sim = self.sim()
        self.assertEqual(sim.evaluate("sum(coord(age), age)", type="int"), 10 + 11 + 12 + 13)
        self.assertEqual(sim.evaluate("sum(coord(sex), sex)", type="int"), 0 + 1)

    def test_indexing_by_member_name_member_number_or_position(self):
        sim = self.sim()
        rates = sim.rt.C["rate"]
        self.assertEqual(sim.evaluate("rate[sex: male, age: 12]"), rates[4 + 2])
        self.assertEqual(sim.evaluate("rate[sex: 1, age: 12]"), rates[4 + 2])
        female = 0.0
        for term in rates[:4]:
            female = female + term
        self.assertEqual(sim.evaluate("sum(rate[sex: female], age)"), female)
        with self.assertRaises(SimError):
            sim.evaluate("rate[sex: male, age: 14]")
        with self.assertRaises(SimError):
            sim.evaluate("rate[sex: 2, age: 10]")

    def test_cohort_shift_moves_everyone_up_and_keeps_the_top_group(self):
        sim = self.sim("""
            [var.shifted]
            type = "int"
            unit = "1"
            phase = "one"
            dims = ["sex", "age"]
            expr = "cohort_shift(count, age)"
        """)
        sim.step()
        counts, shifted = sim.rt.C["count"], sim.rt.C["shifted"]
        for s in range(2):
            c = counts[s * 4: s * 4 + 4]
            self.assertEqual(shifted[s * 4: s * 4 + 4], [0, c[0], c[1], c[2] + c[3]])

    def test_a_dimensioned_var_can_be_read_through_prev(self):
        sim = self.sim("""
            [state.level]
            type = "int"
            unit = "1"
            phase = "one"
            dims = ["sex", "age"]
            initial = 0
            next = "level + count"

            [var.seen]
            type = "int"
            unit = "1"
            phase = "one"
            dims = ["sex", "age"]
            initial = 0
            expr = "level"

            [var.growth]
            type = "int"
            unit = "1"
            phase = "one"
            expr = "sum(seen - prev(seen), sex, age)"
        """)
        rows = [sim.step() for _ in range(3)]
        total = sum(sim.rt.C["count"])
        self.assertEqual([r["growth"] for r in rows], [0, total, total])


class CohortModel(unittest.TestCase):
    def test_ageing_alone_neither_creates_nor_loses_anyone(self):
        sim = Simulation(load_model(COHORT), params={"mortality": 0.0, "fertility": 0.0, "migration_rate": 0.0})
        start = sum(sim.rt.C["population"])
        rows = sim.run(24)
        for row in rows:
            self.assertTrue(math.isclose(row["total_population"], start, rel_tol=1e-12))

    def test_the_whole_number_cohort_moves_up_a_band_each_step(self):
        rows = Simulation(load_model(COHORT)).run(36)
        # Five bands of 1,000 to start; 16 x 10 people join the bottom band each step.
        self.assertEqual([r["cohort_total"] for r in rows], [5000 + 160 * (t + 1) for t in range(36)])

    def test_records_look_up_a_value_by_their_region(self):
        rows = Simulation(load_model(COHORT)).run(1)
        rate = {0: 0.25 * 1.0002, 1: 0.25 * 0.9999, 2: 0.25 * 1.0004}
        expected = 0.0
        for weight, code in ((40, 0), (25, 1), (60, 2), (10, 2)):
            expected = expected + float(weight) * rate[code]
        self.assertEqual(rows[0]["town_rate_total"], expected)

    def test_matches_the_recorded_hashes(self):
        with open(COHORT / "golden" / "base.hashes.csv", newline="", encoding="utf-8") as handle:
            golden = [row["hash"] for row in csv.DictReader(handle)]
        self.assertEqual(len(golden), 36)
        self.assertEqual([r["hash"] for r in Simulation(load_model(COHORT), seed=1).run(36)], golden)

    def test_a_copy_of_the_model_loads_the_same(self):
        with tempfile.TemporaryDirectory() as folder:
            copy = Path(folder) / "cohort"
            shutil.copytree(COHORT, copy)
            self.assertEqual(load_model(copy).model_hash, load_model(COHORT).model_hash)


if __name__ == "__main__":
    unittest.main()
