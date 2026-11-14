"""The formula language and the loader's checks (docs/spec/02-formula-language-v0.md)."""

from __future__ import annotations

import math
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from polisim_oracle import FormulaError, ModelError, SimError, Simulation, load_model  # noqa: E402
from polisim_oracle.expr import compile_formula, marginal_amount  # noqa: E402
from polisim_oracle.model import Decl, Entity, Table, convert  # noqa: E402
from polisim_oracle.rng import fnv1a32, philox4x32_10, uniform  # noqa: E402
from polisim_oracle.sim import Runtime  # noqa: E402
from polisim_oracle.units import parse_unit  # noqa: E402


class Scope:
    """A hand-built scope: three scalars, two household columns, one tax table."""

    def __init__(self):
        gbp_month, per_hh = parse_unit("GBP/month"), parse_unit("GBP/month/household")
        self.step_unit = parse_unit("month")
        self.symbols = {
            "sales": Decl("sales", "var", "int", gbp_month),
            "stock": Decl("stock", "account", "int", parse_unit("GBP")),
            "rate": Decl("rate", "param", "real", parse_unit("1")),
            "allowance": Decl("allowance", "param", "int", per_hh),
            "wage": Decl("wage", "column", "int", per_hh, entity="household"),
            "working": Decl("working", "state", "bool", parse_unit("1"), entity="household"),
        }
        self.tables = {"bands": Table("bands", per_hh, [("allowance", "rate"), ("allowance * 4", "rate * 2.0")])}
        self.streams = {"draws": fnv1a32("draws")}
        self.entities = {"household": Entity("household", [10, 11, 12], [2, 3, 5], {})}
        self.rt = Runtime(seed=99)
        self.rt.S.update(sales=1200, stock=5000, rate=0.2, allowance=100_000)
        self.rt.C.update(wage=[150_000, 90_000, 700_000], working=[True, False, True])
        self.rt.PS.update(sales=1000, stock=4000)
        self.rt.PC.update(working=[False, False, True])

    def value(self, src, typ="int", unit="1", ctx=None, record=0):
        fn, _, _ = compile_formula(src, self, self.rt, ctx, typ, parse_unit(unit), "test")
        return fn(record)


class Arithmetic(unittest.TestCase):
    def setUp(self):
        self.s = Scope()

    def test_precedence_and_grouping(self):
        self.assertEqual(self.s.value("1 + 2 * 3"), 7)
        self.assertEqual(self.s.value("(1 + 2) * 3"), 9)
        self.assertEqual(self.s.value("-2 * 3 - -1"), -5)
        self.assertEqual(self.s.value("10 - 4 - 3"), 3)
        self.assertIs(self.s.value("not true or true", "bool"), True)
        self.assertIs(self.s.value("1 < 2 and not (2 < 1)", "bool"), True)
        self.assertEqual(self.s.value("1_000 + 1"), 1001)

    def test_division_is_always_real_and_needs_explicit_rounding(self):
        self.assertEqual(self.s.value("7 / 2", "real"), 3.5)
        with self.assertRaises(FormulaError):
            self.s.value("7 / 2", "int")
        self.assertEqual(self.s.value("floor(7 / 2)"), 3)

    def test_round_is_half_to_even(self):
        cases = {"0.5": 0, "1.5": 2, "2.5": 2, "3.5": 4, "-0.5": 0, "-1.5": -2, "-2.5": -2, "2.5000001": 3}
        for text, want in cases.items():
            self.assertEqual(self.s.value(f"round({text})"), want, text)
        self.assertEqual(self.s.value("floor(-0.5)"), -1)
        self.assertEqual(self.s.value("ceil(0.2)"), 1)

    def test_whole_number_overflow_is_an_error(self):
        with self.assertRaises(SimError):
            self.s.value("9223372036854775807 + 1")
        with self.assertRaises(SimError):
            self.s.value("4294967296 * 4294967296")

    def test_real_division_follows_ieee_754(self):
        self.assertEqual(self.s.value("1.0 / 0.0", "real"), math.inf)
        self.assertEqual(self.s.value("-1.0 / 0.0", "real"), -math.inf)
        self.assertTrue(math.isnan(self.s.value("0.0 / 0.0", "real")))
        self.assertEqual(self.s.value("safe_div(1.0, 0.0, 7.5)", "real"), 7.5)
        self.assertEqual(self.s.value("select(false, 1.0 / 0.0, 2.0)", "real"), 2.0)

    def test_evaluation_is_strict(self):
        # The untaken branch is still evaluated, so its error still counts.
        with self.assertRaises(SimError):
            self.s.value("select(false, round(1.0 / 0.0), 2)")
        with self.assertRaises(SimError):
            self.s.value("true or round(0.0 / 0.0) == 0", "bool")

    def test_muldiv_floors_and_rejects_bad_divisors(self):
        self.assertEqual(self.s.value("muldiv(7, 10, 3)"), 23)
        self.assertEqual(self.s.value("muldiv(-7, 10, 3)"), -24)
        # The product needs more than 64 bits; only the result has to fit.
        self.assertEqual(self.s.value("muldiv(4611686018427387904, 6, 4)"), 6917529027641081856)
        with self.assertRaises(SimError):
            self.s.value("muldiv(4611686018427387904, 6, 3)")
        with self.assertRaises(SimError):
            self.s.value("muldiv(1, 1, 0)")

    def test_min_max_clamp(self):
        self.assertEqual(self.s.value("min(3, 2)"), 2)
        self.assertEqual(self.s.value("max(3, 2.5)", "real"), 3.0)
        self.assertEqual(self.s.value("clamp(5, 0, 3)"), 3)
        self.assertEqual(self.s.value("clamp(-5, 0, 3)"), 0)
        self.assertEqual(self.s.value("abs(-4)"), 4)


class Units(unittest.TestCase):
    def setUp(self):
        self.s = Scope()

    def test_adding_different_units_is_rejected(self):
        with self.assertRaises(FormulaError):
            self.s.value("sales + stock", unit="GBP/month")
        with self.assertRaises(FormulaError):
            self.s.value("sales + 100", unit="GBP/month")
        with self.assertRaises(FormulaError):
            self.s.value("sales < stock", "bool")

    def test_the_literal_zero_fits_any_unit(self):
        self.assertEqual(self.s.value("max(sales, 0)", unit="GBP/month"), 1200)
        self.assertEqual(self.s.value("sales + 0", unit="GBP/month"), 1200)

    def test_units_multiply_and_divide(self):
        self.assertEqual(self.s.value("round(rate * sales)", unit="GBP/month"), 240)
        self.assertEqual(self.s.value("sales / sales", "real"), 1.0)
        self.assertEqual(self.s.value("per_step(stock) + sales", unit="GBP/month"), 6200)
        self.assertEqual(self.s.value("times_step(sales) + stock", unit="GBP"), 6200)

    def test_the_result_must_have_the_declared_unit(self):
        with self.assertRaises(FormulaError):
            self.s.value("sales", unit="GBP")


class TablesAggregatesAndLags(unittest.TestCase):
    def setUp(self):
        self.s = Scope()

    def test_marginal_schedule(self):
        # 20% from 1,000 to 4,000 and 40% above, amounts in pence.
        self.assertEqual(marginal_amount(500_000, [100_000, 400_000], [0.2, 0.4], "t"), 100_000)
        self.assertEqual(marginal_amount(50_000, [100_000, 400_000], [0.2, 0.4], "t"), 0)
        self.assertEqual(marginal_amount(100_001, [100_000, 400_000], [0.2, 0.4], "t"), 0)
        self.assertEqual(marginal_amount(100_003, [100_000, 400_000], [0.2, 0.4], "t"), 1)
        with self.assertRaises(SimError):
            marginal_amount(1, [400_000, 100_000], [0.2, 0.4], "t")
        per_hh = "GBP/month/household"
        self.assertEqual(self.s.value("marginal(wage, bands)", unit=per_hh, ctx="household", record=2),
                         round(0.2 * 300_000 + 0.4 * 300_000))

    def test_weighted_aggregates(self):
        self.assertEqual(self.s.value("wsum(household, wage)", unit="GBP/month"),
                         2 * 150_000 + 3 * 90_000 + 5 * 700_000)
        self.assertEqual(self.s.value("wsum(household, select(working, wage, 0))", unit="GBP/month"),
                         2 * 150_000 + 5 * 700_000)
        self.assertEqual(self.s.value("wcount(household, working)", unit="household"), 7)
        self.assertEqual(self.s.value("wcount(household, true)", unit="household"), 10)

    def test_columns_cannot_leak_into_national_formulas(self):
        with self.assertRaises(FormulaError):
            self.s.value("wage", unit="GBP/month/household")
        with self.assertRaises(FormulaError):
            self.s.value("wsum(household, wage)", unit="GBP/month", ctx="household")

    def test_prev_reads_last_step(self):
        self.assertEqual(self.s.value("sales - prev(sales)", unit="GBP/month"), 200)
        self.assertIs(self.s.value("working and not prev(working)", "bool", ctx="household", record=0), True)
        with self.assertRaises(FormulaError):
            self.s.value("prev(rate)", "real")

    def test_random_draws_depend_only_on_seed_stream_record_and_step(self):
        first = self.s.value("rand(draws)", "real", ctx="household", record=1)
        self.assertEqual(first, uniform(99, fnv1a32("draws"), 11, 0))
        self.assertTrue(0.0 <= first < 1.0)
        self.s.rt.step = 1
        self.assertNotEqual(self.s.value("rand(draws)", "real", ctx="household", record=1), first)

    def test_philox_known_answers(self):
        # Vectors from the Random123 reference distribution.
        self.assertEqual(philox4x32_10((0, 0, 0, 0), (0, 0)),
                         (0x6627E8D5, 0xE169C58D, 0xBC57AC4C, 0x9B00DBD8))
        self.assertEqual(philox4x32_10((0xFFFFFFFF,) * 4, (0xFFFFFFFF,) * 2),
                         (0x408F276D, 0x41C83B0E, 0xA20BC7C6, 0x6D5451FD))
        self.assertEqual(philox4x32_10((0x243F6A88, 0x85A308D3, 0x13198A2E, 0x03707344), (0xA4093822, 0x299F31D0)),
                         (0xD16CFE09, 0x94FDCCEB, 0x5001E420, 0x24126EA1))


MINIMAL = """
[model]
id = "mini"
format = 0
currency = "GBP"
minor_units = 100
step = "month"
phases = ["one", "two"]

[sector.public]
[sector.private]

[instrument.money]
unit = "GBP"
issuer = "public"

[account.public_money]
sector = "public"
instrument = "money"

[account.private_money]
sector = "private"
instrument = "money"
initial = 100.50
range = [0, inf]

[lever.grant]
type = "money"
unit = "GBP/month"
default = 10
range = [0, 1000]
"""


class Loader(unittest.TestCase):
    def build(self, extra: str):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "model.toml").write_text(MINIMAL + textwrap.dedent(extra), encoding="utf-8")
            return Simulation(load_model(folder))

    def test_a_flow_moves_money_between_two_accounts(self):
        sim = self.build("""
            [flow.grants]
            from = "public"
            to = "private"
            phase = "one"
            expr = "grant"
        """)
        row = sim.step()
        self.assertEqual((row["private_money"], row["public_money"]), (11_050, -11_050))

    def test_money_values_are_read_in_major_units_and_stored_exactly(self):
        sim = self.build("")
        self.assertEqual(sim.rt.S["private_money"], 10_050)
        with self.assertRaises(ModelError):
            self.build("""
                [param.too_fine]
                type = "money"
                unit = "GBP"
                value = 1.005
            """)

    def test_money_is_scaled_from_the_number_as_typed(self):
        # The same cases are in crates/core/src/model.rs.
        cases = [(2301745961.03, 230174596103), (0.29, 29), (1.1, 110), (-5072066666.6, -507206666660),
                 (24217000000.0, 2421700000000), (1e16, 10**18), (12.5, 1250)]
        for raw, pence in cases:
            self.assertEqual(convert(raw, "int", True, 100, "x"), pence)
        self.assertEqual(convert(3.0, "int", True, 1, "x"), 3)
        for raw in (1.005, 0.123456789, 2301745961.035, 1.5e-7):
            with self.assertRaises(ModelError):
                convert(raw, "int", True, 100, "x")
        with self.assertRaises(ModelError):
            convert(1.5, "int", True, 1, "x")

    def test_reading_a_later_phase_is_rejected(self):
        with self.assertRaises(ModelError):
            self.build("""
                [var.early]
                type = "money"
                unit = "GBP/month"
                phase = "one"
                expr = "late"
                [var.late]
                type = "money"
                unit = "GBP/month"
                phase = "two"
                expr = "grant"
            """)

    def test_circular_formulas_are_rejected(self):
        with self.assertRaises(ModelError):
            self.build("""
                [var.a]
                type = "money"
                unit = "GBP/month"
                phase = "one"
                expr = "b"
                [var.b]
                type = "money"
                unit = "GBP/month"
                phase = "one"
                expr = "a"
            """)

    def test_prev_breaks_a_cycle_but_needs_an_initial_value(self):
        text = """
            [var.a]
            type = "money"
            unit = "GBP/month"
            phase = "one"
            {initial}
            expr = "prev(a) + grant"
        """
        with self.assertRaises(ModelError):
            self.build(text.format(initial=""))
        sim = self.build(text.format(initial="initial = 5"))
        self.assertEqual([sim.step()["a"] for _ in range(3)], [1500, 2500, 3500])

    def test_a_unit_error_in_a_model_file_names_the_formula(self):
        with self.assertRaises(FormulaError) as caught:
            self.build("""
                [var.wrong]
                type = "money"
                unit = "GBP/month"
                phase = "one"
                expr = "private_money + grant"
            """)
        self.assertIn("var wrong", str(caught.exception))
        self.assertIn("private_money + grant", str(caught.exception))

    def test_run_time_checks_stop_the_run(self):
        overdraw = self.build("""
            [flow.levy]
            from = "private"
            to = "public"
            phase = "one"
            expr = "grant * 20"
        """)
        with self.assertRaises(SimError):  # balance would leave its declared range
            overdraw.step()
        negative = self.build("""
            [flow.backwards]
            from = "public"
            to = "private"
            phase = "one"
            expr = "0 - grant"
        """)
        with self.assertRaises(SimError):
            negative.step()

    def test_commands_change_levers_and_are_range_checked(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "model.toml").write_text(MINIMAL, encoding="utf-8")
            m = load_model(folder)
            sim = Simulation(m, commands={1: {"grant": 25}})
            self.assertEqual([sim.step()["grant"] for _ in range(2)], [1000, 2500])
            with self.assertRaises(SimError):
                Simulation(m, commands={0: {"grant": 5000}}).step()


if __name__ == "__main__":
    unittest.main()


class Exp(unittest.TestCase):
    """Stage S5.1: exp by a fixed algorithm (docs/spec/02-formula-language-v0.md)."""

    def test_within_two_units_in_the_last_place_of_the_c_library(self):
        import math
        import random
        import struct

        from polisim_oracle.expr import exp_fixed

        def ulps(a: float, b: float) -> int:
            return abs(struct.unpack("<q", struct.pack("<d", a))[0] - struct.unpack("<q", struct.pack("<d", b))[0])
        rng = random.Random(51)
        for _ in range(20000):
            x = rng.choice([rng.uniform(-708.0, 709.0), rng.uniform(-30.0, 30.0), rng.uniform(-0.4, 0.4)])
            self.assertLessEqual(ulps(exp_fixed(x), math.exp(x)), 2, x)

    def test_limits(self):
        import math

        from polisim_oracle.expr import exp_fixed
        self.assertEqual(exp_fixed(0.0), 1.0)
        self.assertEqual(exp_fixed(709.5), math.inf)
        self.assertEqual(exp_fixed(-708.5), 0.0)
        self.assertTrue(math.isnan(exp_fixed(math.nan)))

    def test_in_a_formula(self):
        s = Scope()
        self.assertAlmostEqual(s.value("exp(rate) / (1.0 + exp(rate))", "real"), 0.549833997312478, places=12)
        with self.assertRaises(Exception):
            s.value("exp(sales)", "real")  # money has a unit


class LnSqrtPow(unittest.TestCase):
    """Stage S10.6: ln, sqrt and pow by fixed algorithms (docs/spec/02-formula-language-v0.md)."""

    def test_ln_within_two_units_in_the_last_place_of_the_c_library(self):
        import math
        import random
        import struct

        from polisim_oracle.expr import ln_fixed

        def ulps(a: float, b: float) -> int:
            return abs(struct.unpack("<q", struct.pack("<d", a))[0] - struct.unpack("<q", struct.pack("<d", b))[0])
        rng = random.Random(106)
        for _ in range(20000):
            x = rng.choice([rng.uniform(0.5, 2.0), rng.uniform(0.999, 1.001), math.exp(rng.uniform(-744.0, 709.0)),
                            rng.uniform(0.0, 1e9)])
            if x > 0.0:
                self.assertLessEqual(ulps(ln_fixed(x), math.log(x)), 2, x)

    def test_limits(self):
        import math

        from polisim_oracle.expr import ln_fixed, pow_fixed, sqrt_fixed
        self.assertEqual((ln_fixed(1.0), ln_fixed(2.0), ln_fixed(5e-324)), (0.0, math.log(2.0), -744.4400719213812))
        self.assertEqual((ln_fixed(0.0), ln_fixed(math.inf)), (-math.inf, math.inf))
        self.assertTrue(math.isnan(ln_fixed(-1.0)) and math.isnan(ln_fixed(math.nan)))
        self.assertEqual(sqrt_fixed(2.0), math.sqrt(2.0))
        self.assertTrue(math.isnan(sqrt_fixed(-1.0)))
        self.assertEqual((pow_fixed(5.0, 2.0), pow_fixed(-2.0, 3.0), pow_fixed(-2.0, -2.0)), (25.0, -8.0, 0.25))
        self.assertEqual((pow_fixed(math.nan, 0.0), pow_fixed(0.0, -1.0), pow_fixed(-0.0, -1.0)),
                         (1.0, math.inf, -math.inf))
        self.assertTrue(math.isnan(pow_fixed(-2.0, 2.5)) and math.isnan(pow_fixed(1.0, math.nan)))
        self.assertEqual((pow_fixed(0.0, 0.5), pow_fixed(0.0, -0.5)), (0.0, math.inf))
        self.assertEqual((pow_fixed(math.inf, 0.5), pow_fixed(math.inf, -0.5)), (math.inf, 0.0))

    def test_in_a_formula(self):
        s = Scope()
        self.assertAlmostEqual(s.value("pow(1.0 + rate, 12)", "real"), 1.2 ** 12, places=12)
        self.assertAlmostEqual(s.value("exp(ln(2.0) * 0.5) - sqrt(2.0)", "real"), 0.0, places=15)
        for bad in ("ln(sales)", "sqrt(sales)", "pow(sales, 2)", "pow(2.0)"):
            with self.assertRaises(Exception):
                s.value(bad, "real")
