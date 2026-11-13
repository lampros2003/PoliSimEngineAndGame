"""Formula language v0: tokenizer, parser, static checks (types and units), evaluation.

This file is the executable definition of the language in docs/spec/02-formula-language-v0.md.
It favours being obviously right over being fast: every formula becomes a tree of small
closures, and per-entity formulas are evaluated one record at a time.

Evaluation is strict. Every argument of every function is evaluated, including both
branches of select() and both sides of and/or, so a run-time error anywhere in a formula
is an error regardless of which branch is taken.
"""

from __future__ import annotations

import math
import operator
import re
from dataclasses import dataclass
from typing import Callable

from . import units as U
from .rng import uniform

I64_MIN = -(1 << 63)
I64_MAX = (1 << 63) - 1


class FormulaError(Exception):
    """A formula is malformed (syntax, type or unit error). Raised at load time."""


class SimError(Exception):
    """A formula or posting produced an illegal value at run time."""


# --------------------------------------------------------------------------- parsing

_TOKEN = re.compile(
    r"\s*(?:(?P<num>\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)"
    r"|(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
    r"|(?P<op><=|>=|==|!=|[-+*/()<>,]))"
)
_KEYWORDS = {"and", "or", "not", "true", "false"}


def tokenize(src: str) -> list[tuple[str, object]]:
    tokens: list[tuple[str, object]] = []
    text = src.rstrip()
    pos = 0
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if m is None:
            raise FormulaError(f"unexpected character at column {pos + 1}")
        pos = m.end()
        if m.lastgroup == "num":
            raw = m.group("num").replace("_", "")
            if any(c in raw for c in ".eE"):
                tokens.append(("real", float(raw)))
            else:
                value = int(raw)
                if value > I64_MAX:
                    raise FormulaError("integer literal does not fit in 64 bits")
                tokens.append(("int", value))
        elif m.lastgroup == "name":
            tokens.append(("name", m.group("name")))
        else:
            tokens.append(("op", m.group("op")))
    tokens.append(("end", None))
    return tokens


class _Parser:
    """Recursive descent. Precedence, loosest first: or, and, not, comparison, + -, * /, unary -."""

    def __init__(self, tokens: list[tuple[str, object]]):
        self.tokens = tokens
        self.pos = 0

    def peek(self) -> tuple[str, object]:
        return self.tokens[self.pos]

    def take(self) -> tuple[str, object]:
        tok = self.tokens[self.pos]
        self.pos += 1
        return tok

    def accept_op(self, *ops: str) -> str | None:
        kind, value = self.peek()
        if kind == "op" and value in ops:
            self.pos += 1
            return value  # type: ignore[return-value]
        return None

    def accept_word(self, word: str) -> bool:
        if self.peek() == ("name", word):
            self.pos += 1
            return True
        return False

    def expr(self):
        node = self.conj()
        while self.accept_word("or"):
            node = ("bin", "or", node, self.conj())
        return node

    def conj(self):
        node = self.negation()
        while self.accept_word("and"):
            node = ("bin", "and", node, self.negation())
        return node

    def negation(self):
        if self.accept_word("not"):
            return ("not", self.negation())
        return self.comparison()

    def comparison(self):
        node = self.sum()
        op = self.accept_op("<", "<=", ">", ">=", "==", "!=")
        if op:
            node = ("bin", op, node, self.sum())
        return node

    def sum(self):
        node = self.product()
        while op := self.accept_op("+", "-"):
            node = ("bin", op, node, self.product())
        return node

    def product(self):
        node = self.unary()
        while op := self.accept_op("*", "/"):
            node = ("bin", op, node, self.unary())
        return node

    def unary(self):
        if self.accept_op("-"):
            return ("neg", self.unary())
        return self.primary()

    def primary(self):
        kind, value = self.take()
        if kind in ("int", "real"):
            return (kind, value)
        if kind == "name":
            if value == "true":
                return ("bool", True)
            if value == "false":
                return ("bool", False)
            if value in _KEYWORDS:
                raise FormulaError(f"unexpected keyword {value!r}")
            if self.accept_op("("):
                args = []
                if not self.accept_op(")"):
                    while True:
                        args.append(self.expr())
                        if self.accept_op(")"):
                            break
                        if not self.accept_op(","):
                            raise FormulaError("expected ',' or ')' in argument list")
                return ("call", value, args)
            return ("name", value)
        if kind == "op" and value == "(":
            node = self.expr()
            if not self.accept_op(")"):
                raise FormulaError("expected ')'")
            return node
        if kind == "end":
            raise FormulaError("formula ends unexpectedly")
        raise FormulaError(f"unexpected {value!r}")


def parse(src: str):
    parser = _Parser(tokenize(src))
    node = parser.expr()
    if parser.peek()[0] != "end":
        raise FormulaError(f"unexpected {parser.peek()[1]!r}")
    return node


# --------------------------------------------------------------------------- numeric rules


def checked(value: int) -> int:
    """Every integer result must fit in a signed 64-bit integer."""
    if value < I64_MIN or value > I64_MAX:
        raise SimError("integer overflow (result does not fit in 64 bits)")
    return value


def real_to_int(x: float, mode: str) -> int:
    """round = half to even, floor = toward minus infinity, ceil = toward plus infinity."""
    if x != x or x == math.inf or x == -math.inf:
        raise SimError(f"{mode}() of a non-finite value")
    if mode == "round":
        value = round(x)
    elif mode == "floor":
        value = math.floor(x)
    else:
        value = math.ceil(x)
    return checked(value)


def ieee_div(x: float, y: float) -> float:
    """IEEE 754 division: x/0 is an infinity or NaN, never an exception."""
    if y == 0.0:
        if x != x or x == 0.0:
            return math.nan
        return math.copysign(math.inf, x) * math.copysign(1.0, y)
    return x / y


def marginal_amount(x: int, lows: list[int], rates: list[float], table: str) -> int:
    """Marginal-rate schedule. Band k covers [lows[k], lows[k+1]) and the last band is open.

    acc starts at 0.0; for each band in order: acc = acc + rate * real(slice), where slice
    is the part of x inside the band. The result is acc rounded half to even.
    """
    acc = 0.0
    last = len(lows) - 1
    for k, low in enumerate(lows):
        part = x - low
        if k < last:
            width = lows[k + 1] - low
            if width < 0:
                raise SimError(f"table {table!r}: band thresholds must not descend")
            if part > width:
                part = width
        if part < 0:
            part = 0
        acc = acc + rates[k] * float(checked(part))
    return real_to_int(acc, "round")


# --------------------------------------------------------------------------- compilation


@dataclass
class Built:
    type: str  # "int" | "real" | "bool"
    unit: U.Unit | None  # None only for the literal zero, which fits any unit
    fn: Callable[[int], object]  # argument: record index (ignored by scalar formulas)


def _as_real(b: Built) -> Callable[[int], float]:
    if b.type == "real":
        return b.fn  # type: ignore[return-value]
    f = b.fn
    return lambda i: float(f(i))  # exact below 2^53, round-to-nearest-even above


_COMPARE = {"<": operator.lt, "<=": operator.le, ">": operator.gt, ">=": operator.ge,
            "==": operator.eq, "!=": operator.ne}
_LAGGABLE = {"var", "flow", "state", "account", "lever"}


class _Builder:
    """Turns a syntax tree into a closure while checking types and units.

    `scope` supplies: symbols (name -> declaration with .kind/.type/.unit/.entity),
    tables, streams, entities (name -> object with .ids and .weights) and step_unit.
    `rt` is the run-time store: S / C hold current scalars / columns, PS / PC hold the
    values at the end of the previous step, plus seed and step.
    """

    def __init__(self, scope, rt):
        self.scope = scope
        self.rt = rt
        self.deps: set[str] = set()  # names read at their current-step value
        self.lagged: set[str] = set()  # names read through prev()

    # ---- leaves

    def build(self, node, ctx: str | None) -> Built:
        kind = node[0]
        if kind == "int":
            v = node[1]
            return Built("int", None if v == 0 else U.ONE, lambda i: v)
        if kind == "real":
            v = node[1]
            return Built("real", None if v == 0.0 else U.ONE, lambda i: v)
        if kind == "bool":
            v = node[1]
            return Built("bool", U.ONE, lambda i: v)
        if kind == "name":
            return self._name(node[1], ctx, lagged=False)
        if kind == "neg":
            a = self._number(self.build(node[1], ctx), "unary minus")
            f = a.fn
            if a.type == "int":
                return Built("int", a.unit, lambda i: checked(-f(i)))
            return Built("real", a.unit, lambda i: -f(i))
        if kind == "not":
            a = self._boolean(self.build(node[1], ctx), "not")
            f = a.fn
            return Built("bool", U.ONE, lambda i: not f(i))
        if kind == "bin":
            return self._binary(node[1], self.build(node[2], ctx), self.build(node[3], ctx))
        if kind == "call":
            handler = getattr(self, "_fn_" + node[1], None)
            if handler is None:
                raise FormulaError(f"unknown function {node[1]!r}")
            return handler(node[2], ctx)
        raise AssertionError(kind)

    def _name(self, name: str, ctx: str | None, lagged: bool) -> Built:
        sym = self.scope.symbols.get(name)
        if sym is None:
            raise FormulaError(f"unknown name {name!r}")
        (self.lagged if lagged else self.deps).add(name)
        if sym.entity is None:
            store = self.rt.PS if lagged else self.rt.S
            return Built(sym.type, sym.unit, lambda i: store[name])
        if ctx != sym.entity:
            raise FormulaError(
                f"{name!r} holds one value per {sym.entity}; aggregate it with wsum() or wcount()")
        columns = self.rt.PC if lagged else self.rt.C
        return Built(sym.type, sym.unit, lambda i: columns[name][i])

    @staticmethod
    def _number(b: Built, what: str) -> Built:
        if b.type == "bool":
            raise FormulaError(f"{what} needs a number, not a true/false value")
        return b

    @staticmethod
    def _boolean(b: Built, what: str) -> Built:
        if b.type != "bool":
            raise FormulaError(f"{what} needs a true/false value, not a number")
        return b

    def _args(self, fname: str, args: list, count: int) -> None:
        if len(args) != count:
            raise FormulaError(f"{fname}() takes {count} argument(s), got {len(args)}")

    # ---- operators

    def _binary(self, op: str, a: Built, b: Built) -> Built:
        if op in ("and", "or"):
            fa, fb = self._boolean(a, op).fn, self._boolean(b, op).fn
            if op == "and":
                def fn(i):
                    x, y = fa(i), fb(i)
                    return x and y
            else:
                def fn(i):
                    x, y = fa(i), fb(i)
                    return x or y
            return Built("bool", U.ONE, fn)

        if op in _COMPARE:
            cmp = _COMPARE[op]
            if a.type == "bool" or b.type == "bool":
                if not (a.type == b.type and op in ("==", "!=")):
                    raise FormulaError(f"cannot compare {a.type} with {b.type} using {op}")
                fa, fb = a.fn, b.fn
            else:
                U.unify(a.unit, b.unit, f"comparison {op}")
                if a.type == "int" and b.type == "int":
                    fa, fb = a.fn, b.fn
                else:
                    fa, fb = _as_real(a), _as_real(b)
            return Built("bool", U.ONE, lambda i: cmp(fa(i), fb(i)))

        self._number(a, f"operator {op}")
        self._number(b, f"operator {op}")
        if op in ("+", "-"):
            unit = U.unify(a.unit, b.unit, f"operator {op}")
        elif op == "*":
            unit = U.mul(a.unit, b.unit)
        else:
            unit = U.div(a.unit, b.unit)

        if op == "/":
            fa, fb = _as_real(a), _as_real(b)
            return Built("real", unit, lambda i: ieee_div(fa(i), fb(i)))
        if a.type == "int" and b.type == "int":
            fa, fb = a.fn, b.fn
            if op == "+":
                return Built("int", unit, lambda i: checked(fa(i) + fb(i)))
            if op == "-":
                return Built("int", unit, lambda i: checked(fa(i) - fb(i)))
            return Built("int", unit, lambda i: checked(fa(i) * fb(i)))
        fa, fb = _as_real(a), _as_real(b)
        if op == "+":
            return Built("real", unit, lambda i: fa(i) + fb(i))
        if op == "-":
            return Built("real", unit, lambda i: fa(i) - fb(i))
        return Built("real", unit, lambda i: fa(i) * fb(i))

    # ---- functions

    def _numeric_group(self, fname: str, args: list, ctx: str | None):
        """Arguments that must be numbers with one common unit; int only if all are int."""
        built = [self._number(self.build(a, ctx), f"{fname}()") for a in args]
        unit = None
        for b in built:
            unit = U.unify(unit, b.unit, f"{fname}()")
        if all(b.type == "int" for b in built):
            return "int", unit, [b.fn for b in built]
        return "real", unit, [_as_real(b) for b in built]

    def _fn_min(self, args, ctx):
        self._args("min", args, 2)
        typ, unit, (fa, fb) = self._numeric_group("min", args, ctx)

        def fn(i):
            x, y = fa(i), fb(i)
            return y if y < x else x
        return Built(typ, unit, fn)

    def _fn_max(self, args, ctx):
        self._args("max", args, 2)
        typ, unit, (fa, fb) = self._numeric_group("max", args, ctx)

        def fn(i):
            x, y = fa(i), fb(i)
            return y if y > x else x
        return Built(typ, unit, fn)

    def _fn_clamp(self, args, ctx):
        """clamp(x, lo, hi) is min(max(x, lo), hi)."""
        self._args("clamp", args, 3)
        typ, unit, (fx, flo, fhi) = self._numeric_group("clamp", args, ctx)

        def fn(i):
            x, lo, hi = fx(i), flo(i), fhi(i)
            m = lo if lo > x else x
            return hi if hi < m else m
        return Built(typ, unit, fn)

    def _fn_abs(self, args, ctx):
        self._args("abs", args, 1)
        a = self._number(self.build(args[0], ctx), "abs()")
        f = a.fn
        if a.type == "int":
            return Built("int", a.unit, lambda i: checked(abs(f(i))))
        return Built("real", a.unit, lambda i: math.fabs(f(i)))

    def _to_int(self, mode: str, args, ctx):
        self._args(mode, args, 1)
        a = self._number(self.build(args[0], ctx), f"{mode}()")
        if a.type == "int":
            return a
        f = a.fn
        return Built("int", a.unit, lambda i: real_to_int(f(i), mode))

    def _fn_round(self, args, ctx):
        return self._to_int("round", args, ctx)

    def _fn_floor(self, args, ctx):
        return self._to_int("floor", args, ctx)

    def _fn_ceil(self, args, ctx):
        return self._to_int("ceil", args, ctx)

    def _fn_select(self, args, ctx):
        self._args("select", args, 3)
        fc = self._boolean(self.build(args[0], ctx), "select() condition").fn
        a, b = self.build(args[1], ctx), self.build(args[2], ctx)
        if a.type == "bool" or b.type == "bool":
            if a.type != b.type:
                raise FormulaError("select(): the two branches must be the same kind of value")
            typ, unit, fa, fb = "bool", U.ONE, a.fn, b.fn
        else:
            unit = U.unify(a.unit, b.unit, "select()")
            if a.type == "int" and b.type == "int":
                typ, fa, fb = "int", a.fn, b.fn
            else:
                typ, fa, fb = "real", _as_real(a), _as_real(b)

        def fn(i):
            x, y = fa(i), fb(i)
            return x if fc(i) else y
        return Built(typ, unit, fn)

    def _fn_safe_div(self, args, ctx):
        """safe_div(a, b, d): d when b is zero, otherwise real(a) / real(b)."""
        self._args("safe_div", args, 3)
        a, b, d = (self._number(self.build(x, ctx), "safe_div()") for x in args)
        unit = U.unify(U.div(a.unit, b.unit), d.unit, "safe_div()")
        fa, fb, fd = _as_real(a), _as_real(b), _as_real(d)

        def fn(i):
            x, y, fallback = fa(i), fb(i), fd(i)
            return fallback if y == 0.0 else x / y
        return Built("real", unit, fn)

    def _fn_muldiv(self, args, ctx):
        """muldiv(a, b, c): floor(a*b/c) in exact integer arithmetic; c must be positive."""
        self._args("muldiv", args, 3)
        a, b, c = (self.build(x, ctx) for x in args)
        if not (a.type == b.type == c.type == "int"):
            raise FormulaError("muldiv() needs three whole numbers")
        unit = U.div(U.mul(a.unit, b.unit), c.unit)
        fa, fb, fc = a.fn, b.fn, c.fn

        def fn(i):
            x, y, z = fa(i), fb(i), fc(i)
            if z <= 0:
                raise SimError("muldiv(): the divisor must be positive")
            return checked((x * y) // z)
        return Built("int", unit, fn)

    def _fn_per_step(self, args, ctx):
        """Stock amount -> amount per step (value unchanged, unit divided by the step unit)."""
        self._args("per_step", args, 1)
        a = self._number(self.build(args[0], ctx), "per_step()")
        return Built(a.type, U.div(a.unit, self.scope.step_unit), a.fn)

    def _fn_times_step(self, args, ctx):
        """Amount per step -> stock amount (value unchanged, unit multiplied by the step unit)."""
        self._args("times_step", args, 1)
        a = self._number(self.build(args[0], ctx), "times_step()")
        return Built(a.type, U.mul(a.unit, self.scope.step_unit), a.fn)

    def _fn_marginal(self, args, ctx):
        self._args("marginal", args, 2)
        x = self.build(args[0], ctx)
        if x.type != "int":
            raise FormulaError("marginal(): the amount must be a whole number (money)")
        if args[1][0] != "name" or args[1][1] not in self.scope.tables:
            raise FormulaError("marginal(): the second argument must be the name of a table")
        table = self.scope.tables[args[1][1]]
        U.unify(x.unit, table.unit, f"marginal() with table {table.name!r}")
        lows, rates = [], []
        for low_src, rate_src in table.bands:
            low = self.build(parse(low_src), None)
            rate = self._number(self.build(parse(rate_src), None), "band rate")
            if low.type != "int":
                raise FormulaError(f"table {table.name!r}: 'from' must be a whole number (money)")
            U.unify(low.unit, table.unit, f"table {table.name!r} threshold")
            U.unify(rate.unit, U.ONE, f"table {table.name!r} rate")
            lows.append(low.fn)
            rates.append(_as_real(rate))
        fx, name = x.fn, table.name

        def fn(i):
            return marginal_amount(fx(i), [f(0) for f in lows], [f(0) for f in rates], name)
        return Built("int", x.unit, fn)

    def _fn_prev(self, args, ctx):
        self._args("prev", args, 1)
        if args[0][0] != "name":
            raise FormulaError("prev() takes the name of a variable")
        sym = self.scope.symbols.get(args[0][1])
        if sym is not None and sym.kind not in _LAGGABLE:
            raise FormulaError(f"prev({sym.name}): a {sym.kind} has no previous-step value")
        return self._name(args[0][1], ctx, lagged=True)

    def _fn_rand(self, args, ctx):
        self._args("rand", args, 1)
        if args[0][0] != "name" or args[0][1] not in self.scope.streams:
            raise FormulaError("rand() takes the name of a declared random stream")
        stream, rt = self.scope.streams[args[0][1]], self.rt
        if ctx is None:
            return Built("real", U.ONE, lambda i: uniform(rt.seed, stream, 0, rt.step))
        ids = self.scope.entities[ctx].ids
        return Built("real", U.ONE, lambda i: uniform(rt.seed, stream, ids[i], rt.step))

    def _aggregate(self, fname: str, args, ctx):
        self._args(fname, args, 2)
        if ctx is not None:
            raise FormulaError(f"{fname}() cannot be used inside a per-{ctx} formula")
        if args[0][0] != "name" or args[0][1] not in self.scope.entities:
            raise FormulaError(f"{fname}(): the first argument must be the name of an entity")
        entity = self.scope.entities[args[0][1]]
        return entity, self.build(args[1], entity.name)

    def _fn_wsum(self, args, ctx):
        """Weighted sum over all records. Whole numbers are summed exactly; reals are summed
        left to right in ascending record order, each term being real(weight) * value."""
        entity, inner = self._aggregate("wsum", args, ctx)
        self._number(inner, "wsum()")
        weights, count, f = entity.weights, len(entity.weights), inner.fn
        unit = U.mul(inner.unit, ((entity.name, 1),))
        if inner.type == "int":
            def fn(_):
                total = 0
                for i in range(count):
                    total += weights[i] * f(i)
                return checked(total)
            return Built("int", unit, fn)

        def fn_real(_):
            acc = 0.0
            for i in range(count):
                acc = acc + float(weights[i]) * f(i)
            return acc
        return Built("real", unit, fn_real)

    def _fn_wcount(self, args, ctx):
        entity, inner = self._aggregate("wcount", args, ctx)
        self._boolean(inner, "wcount()")
        weights, count, f = entity.weights, len(entity.weights), inner.fn

        def fn(_):
            total = 0
            for i in range(count):
                if f(i):
                    total += weights[i]
            return checked(total)
        return Built("int", ((entity.name, 1),), fn)


FUNCTIONS = sorted(name[4:] for name in dir(_Builder) if name.startswith("_fn_"))


def compile_formula(src: str, scope, rt, ctx: str | None, want_type: str,
                    want_unit: U.Unit, label: str):
    """Compile `src` for a target of the given type and unit.

    Returns (closure, names read this step, names read through prev()).
    A whole-number result may feed a real target; a real result never feeds a whole-number
    target without an explicit round(), floor() or ceil().
    """
    try:
        builder = _Builder(scope, rt)
        built = builder.build(parse(src), ctx)
        fn = built.fn
        if want_type == "real" and built.type == "int":
            fn = _as_real(built)
        elif built.type != want_type:
            hint = " (use round(), floor() or ceil())" if (want_type, built.type) == ("int", "real") else ""
            raise FormulaError(f"expected a {want_type} value but the formula gives {built.type}{hint}")
        if want_type != "bool":
            U.unify(built.unit, want_unit, "result")
    except (FormulaError, U.UnitError) as exc:
        raise FormulaError(f"{label}: {exc}\n    formula: {src}") from None
    return fn, builder.deps, builder.lagged
