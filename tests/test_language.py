"""The formula language and the loader's checks (docs/spec/02-formula-language-v0.md).

Formulas are evaluated against a small model (SCOPE: three national values, two household
columns, one tax table, one random stream) through the engine's `evaluate`. What the
engine's own functions do at their edges (exp, ln, sqrt and pow against the C library,
the random numbers' known answers, money read from a decimal, the marginal schedule on its
own) is tested in Rust: crates/core/src/program.rs, rng.rs, model.rs and
crates/core/tests/language.rs (tests/README.md lists where each old test went).
"""

from __future__ import annotations

import functools
import math
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from engine import FormulaError, ModelError, SimError, Simulation, load_model  # noqa: E402

# Money in whole units (minor_units = 1), so values read as they are written.
SCOPE = """
[model]
id = "scope"
format = 0
currency = "GBP"
minor_units = 1
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

[account.stock]
sector = "private"
instrument = "money"
initial = 5000

[param.sales]
type = "money"
unit = "GBP/month"
value = 1200

[param.rate]
type = "real"
unit = "1"
value = 0.2

[param.allowance]
type = "money"
unit = "GBP/month/household"
value = 100000

[entity.household]
data = "households.csv"
id = "id"
weight = "weight"

[entity.household.columns.wage]
type = "money"
unit = "GBP/month/household"

[state.working]
entity = "household"
type = "bool"
unit = "1"
phase = "one"
initial = { column = "working0" }
next = "working"

[table.bands]
kind = "marginal"
unit = "GBP/month/household"
bands = [{ from = "allowance", rate = "rate" }, { from = "allowance * 4", rate = "rate * 2.0" }]

[stream.draws]
"""
HOUSEHOLDS = "id,weight,wage,working0\n10,2,150000,1\n11,3,90000,0\n12,5,700000,1\n"


def write(folder: Path, model: str, files: dict[str, str] | None = None) -> Path:
    (folder / "model.toml").write_text(model, encoding="utf-8", newline="\n")
    for name, text in (files or {}).items():
        (folder / name).write_text(text, encoding="utf-8", newline="\n")
    return folder


@functools.lru_cache(maxsize=None)
def scope_model():
    with tempfile.TemporaryDirectory() as folder:
        return load_model(write(Path(folder), SCOPE, {"households.csv": HOUSEHOLDS}))


class Scope:
    """A run of SCOPE with seed 99, before its first step."""

    def __init__(self):
        self.sim = Simulation(scope_model(), seed=99)

    def value(self, src, typ="int", unit="1", ctx=None, record=0):
        got = self.sim.evaluate(src, entity=ctx, type=typ, unit=unit)
        return got[record] if ctx else got


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
        # 20% from 100,000 to 400,000 and 40% above. The schedule on its own (rounding at
        # the band edges, bands out of order) is in crates/core/tests/language.rs.
        per_hh = "GBP/month/household"
        self.assertEqual(self.s.value("marginal(wage, bands)", unit=per_hh, ctx="household", record=2),
                         round(0.2 * 300_000 + 0.4 * 300_000))
        self.assertEqual(self.s.value("marginal(wage, bands)", unit=per_hh, ctx="household", record=1), 0)

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
        # A state moved on in phase one is read at its new value in phase two, and prev()
        # gives its value at the end of the step before.
        extra = """
            [state.level]
            type = "money"
            unit = "GBP/month"
            phase = "one"
            initial = 1000
            next = "level + round(level * 0.2)"

            [state.flag]
            entity = "household"
            type = "bool"
            unit = "1"
            phase = "one"
            initial = { column = "working0" }
            next = "true"

            [var.change]
            type = "money"
            unit = "GBP/month"
            phase = "two"
            expr = "level - prev(level)"

            [var.started]
            entity = "household"
            type = "bool"
            unit = "1"
            phase = "two"
            expr = "flag and not prev(flag)"
        """
        with tempfile.TemporaryDirectory() as folder:
            sim = Simulation(load_model(write(Path(folder), SCOPE + textwrap.dedent(extra),
                                              {"households.csv": HOUSEHOLDS})))
        self.assertEqual(sim.step()["change"], 200)
        self.assertEqual(sim.column("started"), [False, True, False])
        with self.assertRaises(FormulaError):
            self.s.value("prev(rate)", "real")

    def test_random_draws_depend_only_on_seed_stream_record_and_step(self):
        # The exact value, philox(seed, stream, record id, step), is checked in
        # crates/core/tests/language.rs.
        first = self.s.value("rand(draws)", "real", ctx="household", record=1)
        self.assertTrue(0.0 <= first < 1.0)
        self.assertEqual(Scope().value("rand(draws)", "real", ctx="household", record=1), first)
        self.s.sim.step()
        self.assertNotEqual(self.s.value("rand(draws)", "real", ctx="household", record=1), first)


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


class Exp(unittest.TestCase):
    """Stage S5.1: exp by a fixed algorithm (docs/spec/02-formula-language-v0.md). Its accuracy
    and limits: crates/core/src/program.rs."""

    def test_in_a_formula(self):
        s = Scope()
        self.assertAlmostEqual(s.value("exp(rate) / (1.0 + exp(rate))", "real"), 0.549833997312478, places=12)
        with self.assertRaises(FormulaError):
            s.value("exp(sales)", "real")  # money has a unit


class LnSqrtPow(unittest.TestCase):
    """Stage S10.6: ln, sqrt and pow by fixed algorithms (docs/spec/02-formula-language-v0.md).
    Their accuracy and limits: crates/core/src/program.rs."""

    def test_in_a_formula(self):
        s = Scope()
        self.assertAlmostEqual(s.value("pow(1.0 + rate, 12)", "real"), 1.2 ** 12, places=12)
        self.assertAlmostEqual(s.value("exp(ln(2.0) * 0.5) - sqrt(2.0)", "real"), 0.0, places=15)
        for bad in ("ln(sales)", "sqrt(sales)", "pow(sales, 2)", "pow(2.0)"):
            with self.assertRaises(FormulaError):
                s.value(bad, "real")


if __name__ == "__main__":
    unittest.main()
