"""Generate conformance/cases.tsv: formulas with the result the oracle gives for each.

    python tools/gen_conformance.py

Each line is: context, result type, result unit, formula, expected. The context is "-"
for a national formula or an entity name for one value per record. The expected field is
"E:static" (the formula is rejected when compiled), "E:runtime" (it fails when
evaluated), or the value(s): whole numbers in decimal, reals as the 16 hex digits of
their IEEE 754 pattern (or "nan"), true/false as T/F, records separated by commas.

The file is committed. Both the oracle's tests and the engine's tests check every line,
so regenerate it only on purpose, and expect the engine to be held to the new file.
"""

from __future__ import annotations

import math
import random
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "oracle"))

from polisim_oracle import FormulaError, SimError, Simulation, load_model  # noqa: E402

SEED = 20261114
WARM_UP_STEPS = 3  # formulas are evaluated after this many steps, so rand() sees step 3
RANDOM_CASES_PER_CONTEXT = 1500

INT_SCALARS = ["i0", "i1", "i2", "i3", "i4", "ibig", "imax", "imin", "t1", "t2", "counter"]
REAL_SCALARS = ["r0", "r1", "r2", "r3", "r4", "rbig", "rtiny", "rate1", "rate2", "lv"]
BOOL_SCALARS = ["bt", "bf"]
INT_COLUMNS = ["ci1", "ci2"]
REAL_COLUMNS = ["cf1", "cf2"]
BOOL_COLUMNS = ["cb1"]
INT_LITERALS = ["0", "1", "2", "3", "7", "10", "100", "1_000", "4611686018427387904", "9223372036854775807"]
REAL_LITERALS = ["0.0", "0.5", "1.5", "2.5", "0.1", "1e-3", "1e300", "3.0", "4.5e15", "0.49999999999999994"]


class Generator:
    """Random formulas that are usually well typed. Everything here is dimensionless."""

    def __init__(self, rng: random.Random, ctx: str | None):
        self.rng = rng
        self.ctx = ctx

    def pick(self, options):
        return options[self.rng.randrange(len(options))]

    def leaf(self, typ: str) -> str:
        use_column = self.ctx is not None and self.rng.random() < 0.5
        if typ == "int":
            if use_column:
                return self.pick(INT_COLUMNS)
            return self.pick(INT_SCALARS) if self.rng.random() < 0.6 else self.pick(INT_LITERALS)
        if typ == "real":
            if use_column:
                return self.pick(REAL_COLUMNS)
            return self.pick(REAL_SCALARS) if self.rng.random() < 0.6 else self.pick(REAL_LITERALS)
        if use_column:
            return self.pick(BOOL_COLUMNS)
        return self.pick(BOOL_SCALARS + ["true", "false"])

    def number(self, depth: int) -> str:
        return self.expr("int" if self.rng.random() < 0.5 else "real", depth)

    def expr(self, typ: str, depth: int) -> str:
        if depth <= 0 or self.rng.random() < 0.22:
            return self.leaf(typ)
        d = depth - 1
        e, n = self.expr, self.number
        if typ == "int":
            forms = [
                lambda: f"{e('int', d)} + {e('int', d)}",
                lambda: f"{e('int', d)} - {e('int', d)}",
                lambda: f"{e('int', d)} * {e('int', d)}",
                lambda: f"({e('int', d)} - {e('int', d)}) * {e('int', d)}",
                lambda: f"-{e('int', d)}",
                lambda: f"min({e('int', d)}, {e('int', d)})",
                lambda: f"max({e('int', d)}, {e('int', d)})",
                lambda: f"clamp({e('int', d)}, {e('int', d)}, {e('int', d)})",
                lambda: f"abs({e('int', d)})",
                lambda: f"round({e('real', d)})",
                lambda: f"floor({e('real', d)})",
                lambda: f"ceil({e('real', d)})",
                lambda: f"round({e('int', d)})",
                lambda: f"select({e('bool', d)}, {e('int', d)}, {e('int', d)})",
                lambda: f"muldiv({e('int', d)}, {e('int', d)}, {e('int', d)})",
                # Stage S10.3: div and mod, mostly with a positive divisor.
                lambda: f"div({e('int', d)}, {self.pick(['1', '2', '3', '7', '100', 'i2', 'i4'])})",
                lambda: f"mod({e('int', d)}, {self.pick(['1', '2', '3', '7', '100', 'i2', 'i4'])})",
                lambda: f"div({e('int', d)}, {e('int', d)})",
                lambda: f"mod({e('int', d)}, {e('int', d)})",
                lambda: f"marginal({e('int', d)}, tb)",
                lambda: f"per_step({e('int', d)})",
            ]
            if self.ctx is None:
                forms += [lambda: f"wsum(rec, {Generator(self.rng, 'rec').expr('int', d)})",
                          lambda: f"wcount(rec, {Generator(self.rng, 'rec').expr('bool', d)})"]
        elif typ == "real":
            forms = [
                lambda: f"{n(d)} + {e('real', d)}",
                lambda: f"{e('real', d)} - {n(d)}",
                lambda: f"{n(d)} * {e('real', d)}",
                lambda: f"{n(d)} / {n(d)}",
                lambda: f"{e('real', d)} * ({n(d)} + {n(d)})",
                lambda: f"-{e('real', d)}",
                lambda: f"min({n(d)}, {e('real', d)})",
                lambda: f"max({e('real', d)}, {n(d)})",
                lambda: f"clamp({e('real', d)}, {n(d)}, {n(d)})",
                lambda: f"abs({e('real', d)})",
                lambda: f"select({e('bool', d)}, {n(d)}, {e('real', d)})",
                lambda: f"safe_div({n(d)}, {n(d)}, {n(d)})",
                lambda: f"rand({self.pick(['s1', 's2'])})",
                lambda: f"times_step({e('real', d)})",
            ]
            if self.ctx is None:
                forms.append(lambda: f"wsum(rec, {Generator(self.rng, 'rec').expr('real', d)})")
        else:
            op = self.pick(["<", "<=", ">", ">=", "==", "!="])
            forms = [
                lambda: f"{e('int', d)} {op} {e('int', d)}",
                lambda: f"{n(d)} {op} {e('real', d)}",
                lambda: f"{e('real', d)} {op} {n(d)}",
                lambda: f"{e('bool', d)} and {e('bool', d)}",
                lambda: f"{e('bool', d)} or {e('bool', d)}",
                lambda: f"not {e('bool', d)}",
                lambda: f"not ({e('bool', d)} or {e('bool', d)})",
                lambda: f"{e('bool', d)} == {e('bool', d)}",
                lambda: f"{e('bool', d)} != {e('bool', d)}",
                lambda: f"select({e('bool', d)}, {e('bool', d)}, {e('bool', d)})",
            ]
        return self.pick(forms)()


# Hand-written cases: (context, type, unit, formula). Units, scope rules and rejections.
CURATED = [
    # units that work
    ("-", "int", "GBP/month", "m1 + per_step(m2)"),
    ("-", "int", "GBP", "times_step(m1) + m2"),
    ("-", "int", "GBP/month", "round(k * m2)"),
    ("-", "int", "GBP/month", "max(m1, 0)"),
    ("-", "int", "GBP/month", "m1 - 0"),
    ("-", "real", "1", "m1 / m1"),
    ("-", "real", "1/month", "safe_div(m1, m2, 0.0)"),
    ("-", "int", "GBP/month", "muldiv(m1, i2, i4)"),
    ("-", "int", "GBP/month", "wsum(rec, cm)"),
    ("-", "int", "GBP/month", "wsum(rec, marginal(cm, tm))"),
    ("-", "int", "rec", "wcount(rec, cm > allow)"),
    ("-", "real", "GBP/month", "wsum(rec, cf2 * cm)"),
    ("-", "bool", "1", "m1 > per_step(m2)"),
    ("rec", "int", "GBP/month/rec", "marginal(cm, tm)"),
    ("rec", "int", "GBP/month/rec", "select(cb1, cm, 0)"),
    ("rec", "int", "GBP/month/rec", "min(cm, allow * 2)"),
    ("rec", "real", "GBP/month/rec", "cm * rate1"),
    ("rec", "int", "GBP/month/rec", "round(cm * lv) + allow"),
    ("rec", "int", "1", "ci2 + i1"),
    ("rec", "real", "1", "rand(s1) + rand(s2)"),
    ("-", "real", "1", "rand(s1)"),
    ("-", "int", "1", "prev(counter) + counter"),
    ("-", "real", "1", "prev(lv)"),
    ("-", "real", "1", "r0 + 0.0"),
    ("-", "int", "1", " 1 +  2 "),
    ("-", "int", "1", "1_000 * 1_0"),
    ("-", "real", "1", "1e3 + 2.5E-1"),
    ("-", "real", "1", "i1"),
    ("-", "int", "1", "round(0.5) + round(1.5) + round(2.5) + round(-0.5) + round(-1.5)"),
    ("-", "int", "1", "floor(-0.5) + ceil(-0.5) + floor(0.5) + ceil(0.5)"),
    ("-", "real", "1", "min(0.0, -0.0)"),
    ("-", "real", "1", "min(-0.0, 0.0)"),
    ("-", "real", "1", "max(0.0, -0.0)"),
    ("-", "real", "1", "clamp(-0.0, 0.0, 1.0)"),
    ("-", "real", "1", "0.1 + 0.2"),
    ("-", "real", "1", "1.0 / 3.0 * 3.0"),
    ("-", "real", "1", "rbig * rbig"),
    ("-", "real", "1", "rbig * rbig - rbig * rbig"),
    ("-", "real", "1", "rtiny / 2.0"),
    ("-", "real", "1", "imax + 0.0"),
    ("-", "real", "1", "imax - 1 + 0.0"),
    ("-", "bool", "1", "imax == imax + 0.0"),
    ("-", "bool", "1", "0.0 / 0.0 == 0.0 / 0.0"),
    ("-", "bool", "1", "0.0 / 0.0 != 0.0 / 0.0"),
    ("-", "int", "1", "muldiv(ibig, 6, 4)"),
    ("-", "int", "1", "muldiv(i3, i2, 2)"),
    # Stage S10.3: div and mod round down, so a negative number keeps a remainder from 0 up.
    ("-", "int", "1", "div(i3, 4)"),
    ("-", "int", "1", "mod(i3, 4)"),
    ("-", "int", "1", "div(7, 2)"),
    ("-", "int", "1", "mod(7, 2)"),
    ("-", "int", "1", "div(-7, 2)"),
    ("-", "int", "1", "mod(-7, 2)"),
    ("-", "int", "1", "div(imax, 7)"),
    ("-", "int", "1", "mod(imax, 7)"),
    ("-", "int", "1", "div(imin, 1)"),
    ("-", "int", "1", "mod(imin, 7)"),
    ("-", "int", "1", "div(imin, imax)"),
    ("-", "int", "1", "mod(counter, 12)"),
    ("-", "int", "GBP/month", "div(m1, 4)"),
    ("-", "int", "GBP/month", "mod(m1, 1000)"),
    ("-", "int", "1", "div(m1, m1)"),
    ("rec", "int", "GBP/month/rec", "div(cm, 3)"),
    ("rec", "int", "GBP/month/rec", "mod(cm, 3)"),
    ("-", "int", "1", "marginal(1000, tb)"),
    ("-", "int", "1", "marginal(imax, tb)"),
    ("-", "int", "1", "marginal(imin, tb)"),
    # run-time errors
    ("-", "int", "1", "imax + i1"),
    ("-", "int", "1", "imin - i1"),
    ("-", "int", "1", "-imin"),
    ("-", "int", "1", "abs(imin)"),
    ("-", "int", "1", "ibig * i2"),
    ("-", "int", "1", "muldiv(ibig, 6, 3)"),
    ("-", "int", "1", "muldiv(i1, i1, i0)"),
    ("-", "int", "1", "muldiv(i1, i1, i3)"),
    ("-", "int", "1", "div(i1, i0)"),
    ("-", "int", "1", "mod(i1, i0)"),
    ("-", "int", "1", "div(i1, -3)"),
    ("-", "int", "1", "mod(i1, -3)"),
    ("rec", "int", "1", "div(ci1, ci2)"),
    ("-", "int", "1", "round(rbig)"),
    ("-", "int", "1", "round(1.0 / 0.0)"),
    ("-", "int", "1", "floor(0.0 / 0.0)"),
    ("-", "int", "1", "select(false, round(1.0 / 0.0), 2)"),
    ("-", "bool", "1", "true or round(0.0 / 0.0) == 0"),
    ("-", "int", "1", "round(9223372036854775807.0)"),
    ("-", "int", "1", "round(-9223372036854775808.0)"),
    ("-", "int", "1", "wsum(rec, ci1)"),
    ("-", "int", "1", "wsum(rec, ci1 * 4)"),
    ("rec", "int", "1", "ci1 + i1"),
    ("rec", "int", "1", "ci1 * ci2"),
    # rejected when compiled
    ("-", "int", "1", ""),
    ("-", "int", "1", "1 +"),
    ("-", "int", "1", "(1"),
    ("-", "int", "1", "1 2"),
    ("-", "int", "1", "@"),
    ("-", "real", "1", "1."),
    ("-", "real", "1", "1e"),
    ("-", "int", "1", "9223372036854775808"),
    ("-", "bool", "1", "1 < 2 < 3"),
    ("-", "bool", "1", "1 = 1"),
    ("-", "int", "1", "nope"),
    ("-", "int", "1", "nope(1)"),
    ("-", "int", "1", "min(1)"),
    ("-", "int", "1", "min(1, 2, 3)"),
    ("-", "int", "1", "and"),
    ("-", "int", "1", "1.5"),
    ("-", "int", "1", "7 / 2"),
    ("-", "bool", "1", "1"),
    ("-", "int", "1", "true"),
    ("-", "real", "1", "true"),
    ("-", "bool", "1", "not 1"),
    ("-", "bool", "1", "1 and true"),
    ("-", "int", "1", "true + 1"),
    ("-", "int", "1", "-true"),
    ("-", "int", "1", "select(1, 2, 3)"),
    ("-", "int", "1", "select(true, 1, false)"),
    ("-", "bool", "1", "bt < bf"),
    ("-", "bool", "1", "1 == true"),
    ("-", "int", "1", "div(1.5, 2)"),
    ("-", "int", "1", "mod(r1, 2)"),
    ("-", "int", "1", "div(i1)"),
    ("-", "int", "1", "mod(i1, i2, i3)"),
    ("-", "int", "GBP/month", "mod(m1, m2)"),
    ("-", "bool", "1", "div(bt, 2)"),
    ("-", "int", "1", "muldiv(1.0, 2, 3)"),
    ("-", "int", "1", "marginal(r1, tb)"),
    ("-", "int", "1", "marginal(i1, nope)"),
    ("-", "int", "1", "marginal(i1, i2)"),
    ("-", "int", "GBP/month", "marginal(m1, tb)"),
    ("-", "real", "1", "rand(nope)"),
    ("-", "real", "1", "rand(1)"),
    ("-", "int", "1", "prev(i1)"),
    ("-", "int", "1", "prev(1)"),
    ("-", "int", "1", "prev(nope)"),
    ("-", "int", "1", "ci1"),
    ("-", "int", "1", "wsum(nope, 1)"),
    ("-", "int", "1", "wsum(rec, bt)"),
    ("-", "int", "1", "wcount(rec, 1)"),
    ("-", "int", "1", "wsum(rec, wsum(rec, ci1))"),
    ("rec", "int", "1", "wsum(rec, ci1)"),
    ("rec", "int", "1", "prev(ci1)"),
    ("-", "int", "GBP/month", "m1 + m2"),
    ("-", "int", "GBP/month", "m1 + 1"),
    ("-", "int", "GBP", "m1"),
    ("-", "bool", "1", "m1 < m2"),
    ("-", "int", "GBP/month", "min(m1, m2)"),
    ("-", "int", "GBP/month", "select(bt, m1, m2)"),
    ("-", "real", "1", "safe_div(m1, m2, 0.5)"),
    ("-", "int", "1", "per_step(bt)"),
    ("-", "int", "1", "abs(bt)"),
    ("-", "int", "1", "round(bt)"),
]


def encode(value) -> str:
    if isinstance(value, bool):
        return "T" if value else "F"
    if isinstance(value, int):
        return str(value)
    if value != value:
        return "nan"
    return struct.pack(">d", value).hex()


def expected(sim: Simulation, ctx: str, typ: str, unit: str, formula: str) -> str:
    try:
        result = sim.evaluate(formula, None if ctx == "-" else ctx, typ, unit)
    except FormulaError:
        return "E:static"
    except SimError:
        return "E:runtime"
    if isinstance(result, list):
        return ",".join(encode(v) for v in result)
    return encode(result)


def exp_cases() -> list[tuple[str, str, str, str]]:
    """Stage S5.1: exp over its whole range, at the limits, inside formulas, and refused
    with a unit. Drawn from their own generator, so the cases before them do not change."""
    rng = random.Random(51)
    cases = [
        ("-", "real", "1", "exp(0.0)"),
        ("-", "real", "1", "exp(1)"),
        ("-", "real", "1", "exp(-1.0)"),
        ("-", "real", "1", "exp(709.0)"),
        ("-", "real", "1", "exp(709.0000000000001)"),
        ("-", "real", "1", "exp(-708.0)"),
        ("-", "real", "1", "exp(-708.0000000000001)"),
        ("-", "real", "1", "exp(0.34657359027997264)"),
        ("-", "real", "1", "exp(-0.34657359027997264)"),
        ("-", "real", "1", "exp(0.0 / 0.0)"),
        ("-", "real", "1", "exp(1.0 / 0.0)"),
        ("-", "real", "1", "exp(-1.0 / 0.0)"),
        ("-", "real", "1", "exp(rate1) / (1.0 + exp(rate1))"),
        ("-", "real", "1", "exp(r1 - r1)"),
        ("rec", "real", "1", "exp(rate1 * 3.0)"),
        ("-", "int", "1", "round(exp(5))"),
        ("-", "real", "1", "exp(m1)"),
        ("-", "real", "1", "exp(1.0, 2.0)"),
        ("-", "int", "1", "exp(1.0)"),
        ("-", "real", "1", "exp(true)"),
    ]
    for _ in range(400):
        x = rng.choice([rng.uniform(-750.0, 750.0), rng.uniform(-20.0, 20.0), rng.uniform(-0.5, 0.5),
                        rng.uniform(-1e-6, 1e-6), float(rng.randint(-710, 710))])
        cases.append(("-", "real", "1", f"exp({x!r})"))
    return cases


def power_cases() -> list[tuple[str, str, str, str]]:
    """Stage S10.6: ln, sqrt and pow over their ranges, at their edges, inside formulas and
    per record, and refused with a unit, the wrong count or a true/false value. Drawn from
    their own generator, after exp's, so the cases before them do not change."""
    rng = random.Random(106)
    cases = [
        ("-", "real", "1", "ln(1.0)"),
        ("-", "real", "1", "ln(1)"),
        ("-", "real", "1", "ln(2.0)"),
        ("-", "real", "1", "ln(0.5)"),
        ("-", "real", "1", "ln(10)"),
        ("-", "real", "1", "ln(0.0)"),
        ("-", "real", "1", "ln(-0.0)"),
        ("-", "real", "1", "ln(-1.0)"),
        ("-", "real", "1", "ln(1.0 / 0.0)"),
        ("-", "real", "1", "ln(0.0 / 0.0)"),
        ("-", "real", "1", "ln(5e-324)"),
        ("-", "real", "1", "ln(2.2250738585072014e-308)"),
        ("-", "real", "1", "ln(1.7976931348623157e308)"),
        ("-", "real", "1", "ln(0.7071067811865476)"),
        ("-", "real", "1", "ln(0.7071067811865475)"),
        ("-", "real", "1", "ln(1.0000000000000002)"),
        ("-", "real", "1", "ln(0.9999999999999999)"),
        ("-", "real", "1", "ln(exp(rate1))"),
        ("-", "real", "1", "exp(ln(r1))"),
        ("-", "real", "1", "ln(imax)"),
        ("-", "real", "1", "ln(rtiny)"),
        ("-", "real", "1", "ln(rbig)"),
        ("-", "real", "1", "sqrt(2.0)"),
        ("-", "real", "1", "sqrt(4)"),
        ("-", "real", "1", "sqrt(0.0)"),
        ("-", "real", "1", "sqrt(-0.0)"),
        ("-", "real", "1", "sqrt(-1.0)"),
        ("-", "real", "1", "sqrt(1.0 / 0.0)"),
        ("-", "real", "1", "sqrt(0.0 / 0.0)"),
        ("-", "real", "1", "sqrt(5e-324)"),
        ("-", "real", "1", "sqrt(imax)"),
        ("-", "real", "1", "pow(2.0, 10.0)"),
        ("-", "real", "1", "pow(2, 10)"),
        ("-", "real", "1", "pow(2.0, 0.5)"),
        ("-", "real", "1", "pow(1.05, 12)"),
        ("-", "real", "1", "pow(10.0, -3)"),
        ("-", "real", "1", "pow(-2.0, 0.0)"),
        ("-", "real", "1", "pow(-2.0, 2.0)"),
        ("-", "real", "1", "pow(0.0, 2.0)"),
        ("-", "real", "1", "pow(0.0, -1.0)"),
        ("-", "real", "1", "pow(0.0, 0.0)"),
        ("-", "real", "1", "pow(1.0 / 0.0, 0.5)"),
        ("-", "real", "1", "pow(1.0 / 0.0, -0.5)"),
        ("-", "real", "1", "pow(0.0 / 0.0, 0.0)"),
        ("-", "real", "1", "pow(1.0, 0.0 / 0.0)"),
        ("-", "real", "1", "pow(2.0, 1100.0)"),
        ("-", "real", "1", "pow(2.0, -1100.0)"),
        ("-", "real", "1", "pow(rate1, rate2)"),
        ("-", "real", "1", "pow(r1 * r1, 0.5) - abs(r1)"),
        ("-", "int", "1", "round(pow(i2, 3))"),
        ("-", "int", "1", "round(1.0 / 0.0 * ln(0.0))"),
        ("-", "int", "1", "round(sqrt(-4.0))"),
        ("-", "real", "1", "select(i2 > 0, ln(i2), 0.0)"),
        ("-", "real", "1", "safe_div(ln(r1), sqrt(r2), 0.0)"),
        ("rec", "real", "1", "ln(cf1 + 1.0)"),
        ("rec", "real", "1", "sqrt(abs(cf2))"),
        ("rec", "real", "1", "pow(1.0 + abs(cf1), cf2)"),
        ("rec", "real", "1", "pow(ci1, 2)"),
        ("rec", "int", "1", "round(ln(abs(ci2) + 1) * 1000.0)"),
        ("-", "real", "1", "ln(m1)"),
        ("-", "real", "1", "sqrt(m1)"),
        ("-", "real", "1", "pow(m1, 2.0)"),
        ("-", "real", "1", "pow(2.0, m1)"),
        ("rec", "real", "1", "ln(cm)"),
        ("-", "real", "1", "ln(true)"),
        ("-", "real", "1", "sqrt(bt)"),
        ("-", "real", "1", "pow(2.0, false)"),
        ("-", "real", "1", "ln()"),
        ("-", "real", "1", "ln(1.0, 2.0)"),
        ("-", "real", "1", "sqrt(1.0, 2.0)"),
        ("-", "real", "1", "pow(2.0)"),
        ("-", "real", "1", "pow(1.0, 2.0, 3.0)"),
        ("-", "int", "1", "ln(1.0)"),
        ("-", "int", "1", "sqrt(4)"),
        ("-", "int", "1", "pow(2, 2)"),
        ("-", "real", "GBP/month", "pow(2.0, 2.0)"),
    ]
    for _ in range(200):
        x = rng.choice([rng.uniform(0.0, 4.0), rng.uniform(0.999, 1.001), math.exp(rng.uniform(-744.0, 709.0)),
                        rng.uniform(-1.0, 1e9), float(rng.randint(-5, 10**6))])
        cases.append(("-", "real", "1", f"ln({x!r})"))
    for _ in range(100):
        x = rng.choice([rng.uniform(0.0, 4.0), math.exp(rng.uniform(-744.0, 709.0)), rng.uniform(-1.0, 1e9)])
        cases.append(("-", "real", "1", f"sqrt({x!r})"))
    for _ in range(200):
        x = rng.choice([rng.uniform(0.0, 4.0), rng.uniform(0.5, 1.5), math.exp(rng.uniform(-50.0, 50.0)),
                        rng.uniform(-1.0, 1.0), 0.0])
        y = rng.choice([rng.uniform(-3.0, 3.0), float(rng.randint(-12, 12)), rng.uniform(-400.0, 400.0), 0.5])
        cases.append(("-", "real", "1", f"pow({x!r}, {y!r})"))
    return cases


def quantile_cases() -> list[tuple[str, str, str, str]]:
    """Stage S10.9: quantile over the records' awkward values (ties of 0.0 and -0.0, a
    subnormal, the 64-bit limits, a weight above 32 bits), at the ends and in between, with
    shares that are whole numbers or national formulas, and refused: a share outside 0 to 1
    or with a unit, a value that is not a number, a true/false value, a record formula, the
    wrong count. Drawn from their own generator, after ln's, so the cases before them do
    not change."""
    rng = random.Random(109)
    cases = [
        ("-", "real", "1", "quantile(rec, cf1, 0.5)"),
        ("-", "real", "1", "quantile(rec, cf1, 0.0)"),
        ("-", "real", "1", "quantile(rec, cf1, 1.0)"),
        ("-", "real", "1", "quantile(rec, cf1, 1)"),
        ("-", "real", "1", "quantile(rec, cf2, 0.25)"),
        ("-", "real", "1", "quantile(rec, cf2, rate1)"),
        ("-", "int", "1", "quantile(rec, ci1, 0.5)"),
        ("-", "int", "1", "quantile(rec, ci1, 0.0)"),
        ("-", "int", "1", "quantile(rec, ci1, 1.0)"),
        ("-", "int", "1", "quantile(rec, ci2, 0.999)"),
        ("-", "int", "1", "quantile(rec, ci2, 1e-12)"),
        ("-", "int", "GBP/month/rec", "quantile(rec, cm, 0.5)"),
        ("-", "real", "1", "quantile(rec, cf1 * 0.0, 0.5)"),
        ("-", "real", "1", "quantile(rec, -cf1 * 0.0, 0.5)"),
        ("-", "real", "1", "quantile(rec, cf1, 0.5) + wsum(rec, cf2) / wcount(rec, true)"),
        ("-", "real", "1", "quantile(rec, select(cb1, cf2, -cf2), 0.6)"),
        ("-", "int", "1", "quantile(rec, ci2, i1 / 2.0)"),
        ("-", "real", "1", "quantile(rec, cf1, 1.5)"),
        ("-", "real", "1", "quantile(rec, cf1, -0.1)"),
        ("-", "real", "1", "quantile(rec, cf1, 0.0 / 0.0)"),
        ("-", "real", "1", "quantile(rec, cf1 / 0.0, 0.5)"),
        ("-", "int", "1", "quantile(rec, ci1 + 1, 0.5)"),
        ("-", "real", "1", "quantile(rec, cf1, m1)"),
        ("-", "real", "1", "quantile(rec, cb1, 0.5)"),
        ("-", "real", "1", "quantile(rec, cf1, true)"),
        ("-", "real", "1", "quantile(rec, cf1)"),
        ("-", "real", "1", "quantile(rec, cf1, 0.5, 0.5)"),
        ("-", "real", "1", "quantile(cf1, cf1, 0.5)"),
        ("rec", "real", "1", "quantile(rec, cf1, 0.5)"),
        ("-", "int", "1", "quantile(rec, cf1, 0.5)"),
    ]
    generator = Generator(rng, "rec")
    for _ in range(120):
        share = rng.choice([repr(rng.random()), "0.5", "0.0", "1.0", repr(rng.choice([0.1, 0.25, 0.75, 0.9]))])
        typ = rng.choice(["int", "real"])
        cases.append(("-", typ, "1", f"quantile(rec, {generator.expr(typ, rng.randrange(1, 4))}, {share})"))
    return cases


def curve_cases() -> list[tuple[str, str, str, str]]:
    """Stage S11.1: curves, at and between their points, beyond their ends, with whole
    numbers, money, infinities and not-a-number, per record, and refused: the wrong table,
    unit or count, true/false values, points that do not ascend. Drawn from their own
    generator, after quantile's, so the cases before them do not change."""
    rng = random.Random(111)
    cases = [(ctx, "real", "1", f"curve({x}, tc)") for ctx, x in [
        ("-", "-5.0"), ("-", "-1.0"), ("-", "-0.5"), ("-", "0.0"), ("-", "-0.0"), ("-", "0"), ("-", "0.25"),
        ("-", "r1"), ("-", "1"), ("-", "2.0"), ("-", "1e299"), ("-", "1e300"), ("-", "1e301"), ("-", "rtiny"),
        ("-", "-rtiny"), ("-", "1.0 / 0.0"), ("-", "-1.0 / 0.0"), ("-", "0.0 / 0.0"), ("-", "imax"),
        ("-", "i3"), ("rec", "cf1"), ("rec", "cf2"), ("rec", "ci2")]]
    cases += [
        ("rec", "real", "1", "curve(cm, tcm)"),
        ("rec", "real", "1", "curve(cm + allow, tcm) * 2.0"),
        ("-", "real", "1", "curve(curve(r1, tc), tc)"),
        ("-", "int", "1", "round(curve(r2, tc) * 100.0)"),
        ("-", "real", "1", "curve(0.5, tcd)"),
        ("rec", "real", "1", "curve(cf1, tcd)"),
        ("-", "real", "1", "curve(m1, tc)"),
        ("-", "real", "1", "curve(r1, tcm)"),
        ("-", "real", "1", "curve(r1, tb)"),
        ("-", "int", "1", "marginal(i1, tc)"),
        ("-", "real", "1", "curve(r1, nothing)"),
        ("-", "real", "1", "curve(r1)"),
        ("-", "real", "1", "curve(bt, tc)"),
        ("-", "int", "1", "curve(r1, tc)"),
        ("-", "real", "GBP", "curve(r1, tc)"),
    ]
    for _ in range(150):
        x = rng.choice([repr(rng.uniform(-3.0, 3.0)), repr(rng.uniform(-0.1, 0.6)), repr(float(rng.randint(-2, 3))),
                        repr(rng.uniform(1.9, 2.1)), repr(rng.choice([-1.0, 0.0, 0.5, 2.0]))])
        cases.append(("-", "real", "1", f"curve({x}, tc)"))
    return cases


def counted_quantile_cases() -> list[tuple[str, str, str, str]]:
    """Stage S11.2: quantile with a count per record (people in a household), including
    counts of zero, a count that tips the median, and refused counts: below zero, real,
    with a unit, true/false. After the curves' cases, so those before do not change."""
    rng = random.Random(112)
    cases = [
        ("-", "real", "1", "quantile(rec, cf1, 0.5, 1)"),
        ("-", "real", "1", "quantile(rec, cf1, 0.5, ci2)"),
        ("-", "real", "1", "quantile(rec, cf1, 0.5, select(ci2 > 0, ci2, 0))"),
        ("-", "real", "1", "quantile(rec, cf2, 0.25, abs(ci1) * 0)"),
        ("-", "real", "1", "quantile(rec, cf2, 0.5, select(cb1, 1000000000, 1))"),
        ("-", "int", "1", "quantile(rec, ci1, 1.0, select(ci2 >= 0, ci2, 0))"),
        ("-", "int", "1", "quantile(rec, ci2, 0.0, select(cb1, 0, 3))"),
        ("-", "real", "1", "quantile(rec, cf1, 0.5, ci2 - 10)"),
        ("-", "real", "1", "quantile(rec, cf1, 0.5, cf2)"),
        ("-", "real", "1", "quantile(rec, cf1, 0.5, cm)"),
        ("-", "real", "1", "quantile(rec, cf1, 0.5, cb1)"),
        ("-", "real", "1", "quantile(rec, cf1, 0.5, 1, 1)"),
    ]
    for _ in range(80):
        share = rng.choice(["0.5", "0.1", "0.9", repr(rng.random())])
        times = rng.choice(["1", "abs(ci2)", "select(cb1, 2, 1)", "abs(ci1) * 0 + 3", "select(ci2 > 0, ci2, 0)"])
        cases.append(("-", "real", "1", f"quantile(rec, {rng.choice(['cf1', 'cf2', 'cf1 + cf2', 'cf2 * 2.0'])}, {share}, {times})"))
    return cases


def warmed_up_simulation() -> Simulation:
    sim = Simulation(load_model(ROOT / "conformance" / "model"), seed=SEED)
    sim.run(WARM_UP_STEPS)
    return sim


def main() -> None:
    rng = random.Random(SEED)
    cases = list(CURATED)
    for ctx in ("-", "rec"):
        generator = Generator(rng, None if ctx == "-" else ctx)
        for _ in range(RANDOM_CASES_PER_CONTEXT):
            typ = ("int", "real", "bool")[rng.randrange(3)]
            formula = generator.expr(typ, rng.randrange(1, 5))
            # Now and then ask for the wrong result type, to exercise the rejection.
            want = typ if rng.random() < 0.95 else ("int", "real", "bool")[rng.randrange(3)]
            cases.append((ctx, want, "1", formula))

    cases += exp_cases()
    cases += power_cases()
    cases += quantile_cases()
    cases += curve_cases()
    cases += counted_quantile_cases()

    sim = warmed_up_simulation()
    counts = {"value": 0, "E:static": 0, "E:runtime": 0}
    out = ROOT / "conformance" / "cases.tsv"
    with open(out, "w", encoding="utf-8", newline="") as handle:
        for ctx, typ, unit, formula in cases:
            assert "\t" not in formula and "\n" not in formula
            result = expected(sim, ctx, typ, unit, formula)
            counts[result if result.startswith("E:") else "value"] += 1
            handle.write(f"{ctx}\t{typ}\t{unit}\t{formula}\t{result}\n")
    print(f"wrote {out}: {len(cases)} cases, {counts}")


if __name__ == "__main__":
    main()
