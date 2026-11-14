"""Formula language v0: tokenizer, parser, static checks (types and units), evaluation.

This file is the executable definition of the language in docs/spec/02-formula-language-v0.md.
It favours being obviously right over being fast: every formula becomes a tree of small
closures, and per-entity formulas are evaluated one record at a time.

Evaluation is strict. Every argument of every function is evaluated, including both
branches of select() and both sides of and/or, so a run-time error anywhere in a formula
is an error regardless of which branch is taken.
"""

from __future__ import annotations

import itertools
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
    r"|(?P<op><=|>=|==|!=|[-+*/()<>,\[\]:]))"
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
            if self.accept_op("["):
                # Format 1: x[d: e, ...] fixes dimensions of a dimensioned element.
                coords = []
                while True:
                    kind2, dim = self.take()
                    if kind2 != "name" or dim in _KEYWORDS:
                        raise FormulaError("expected a dimension name inside [ ]")
                    if not self.accept_op(":"):
                        raise FormulaError(f"expected ':' after {dim} inside [ ]")
                    coords.append((dim, self.expr()))
                    if self.accept_op("]"):
                        break
                    if not self.accept_op(","):
                        raise FormulaError("expected ',' or ']' inside [ ]")
                return ("index", value, coords)
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


_EXP_COEFFICIENTS = (2.08767569878681e-09, 2.505210838544172e-08, 2.755731922398589e-07,
                     2.7557319223985893e-06, 2.48015873015873e-05, 0.0001984126984126984,
                     0.001388888888888889, 0.008333333333333333, 0.041666666666666664,
                     0.16666666666666666, 0.5, 1.0, 1.0)


def exp_fixed(x: float) -> float:
    """exp(x) by the fixed algorithm of docs/spec/02-formula-language-v0.md: the same bits
    on every machine (only rounded + - * and an exact scaling by a power of two)."""
    if x != x:
        return x
    if x > 709.0:
        return math.inf
    if x < -708.0:
        return 0.0
    k = round(x * 1.4426950408889634)
    r = (x - k * 0.6931471803691238) - k * 1.9082149292705877e-10
    p = 1.6059043836821613e-10
    for c in _EXP_COEFFICIENTS:
        p = p * r + c
    return math.ldexp(p, k)


_LN_COEFFICIENTS = (0.6666666666666735, 0.3999999999940942, 0.2857142874366239,
                    0.22222198432149784, 0.1818357216161805, 0.15313837699209373,
                    0.14798198605116586)


def ln_fixed(x: float) -> float:
    """The natural logarithm by the fixed algorithm of docs/spec/02-formula-language-v0.md
    (stage S10.6): the same bits on every machine (only rounded + - * / and an exact split
    of x into a fraction and a power of two)."""
    if x != x or x < 0.0:
        return math.nan
    if x == 0.0:
        return -math.inf
    if x == math.inf:
        return x
    m, e = math.frexp(x)
    if m < 0.7071067811865476:
        m, e = m * 2.0, e - 1
    f = m - 1.0
    s = f / (2.0 + f)
    z = s * s
    w = z * z
    lg1, lg2, lg3, lg4, lg5, lg6, lg7 = _LN_COEFFICIENTS
    r = z * (lg1 + w * (lg3 + w * (lg5 + w * lg7))) + w * (lg2 + w * (lg4 + w * lg6))
    half_square = 0.5 * f * f
    k = float(e)
    return k * 0.6931471803691238 - ((half_square - (s * (half_square + r) + k * 1.9082149292705877e-10)) - f)


def sqrt_fixed(x: float) -> float:
    """The square root, correctly rounded as IEEE 754 requires; not-a-number below zero."""
    return math.nan if x < 0.0 else math.sqrt(x)


def pow_fixed(x: float, y: float) -> float:
    """x to the power y (stage S10.6), by docs/spec/02: for a whole y of at most 1,024 in
    size, by repeated squaring (so pow(5, 2) is 25 and a negative x is allowed); otherwise
    exp(y * ln(x)) by the fixed algorithms, with cases for zero, infinity and not-a-number."""
    if y != y:
        return math.nan
    if y == math.floor(y) and abs(y) <= 1024.0:
        n, r, b = int(abs(y)), 1.0, x
        while n > 0:
            if n % 2 == 1:
                r = r * b
            n //= 2
            b = b * b
        if y < 0.0:
            if r == 0.0:
                return math.copysign(math.inf, r)
            r = 1.0 / r
        return r
    if x != x:
        return math.nan
    if x < 0.0:
        return math.nan
    if x == 0.0:
        return 0.0 if y > 0.0 else math.inf
    if x == math.inf:
        return math.inf if y > 0.0 else 0.0
    return exp_fixed(y * ln_fixed(x))


class _Builder:
    """Turns a syntax tree into a closure while checking types and units.

    `scope` supplies: symbols (name -> declaration with .kind/.type/.unit/.entity),
    tables, streams, entities (name -> object with .ids and .weights) and step_unit.
    `rt` is the run-time store: S / C hold current scalars / columns, PS / PC hold the
    values at the end of the previous step, plus seed and step.
    """

    def __init__(self, scope, rt, dims: tuple[str, ...] = ()):
        self.scope = scope
        self.rt = rt
        # Format 1: the dimensions in scope. Inside a formula with dimensions, closures get
        # the current cell's coordinates ({dimension: position}) instead of a record index.
        self.in_scope: tuple[str, ...] = tuple(dims)
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
        if kind == "index":
            return self._index(node, ctx)
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
        dims = getattr(sym, "dims", ())
        if dims:
            missing = [d for d in dims if d not in self.in_scope]
            if missing:
                raise FormulaError(f"{name!r} holds one value per {', '.join(dims)}; {missing[0]} is not in scope "
                                   f"here: sum it with sum({name}, {missing[0]}) or fix it with {name}[{missing[0]}: ...]")
            strides = self._strides(dims)
            columns = self.rt.PC if lagged else self.rt.C

            def cell(i):
                flat = 0
                for d, stride in strides:
                    flat += i[d] * stride
                return columns[name][flat]
            return Built(sym.type, sym.unit, cell)
        if sym.entity is None:
            store = self.rt.PS if lagged else self.rt.S
            return Built(sym.type, sym.unit, lambda i: store[name])
        if ctx != sym.entity:
            raise FormulaError(
                f"{name!r} holds one value per {sym.entity}; aggregate it with wsum() or wcount()")
        columns = self.rt.PC if lagged else self.rt.C
        return Built(sym.type, sym.unit, lambda i: columns[name][i])

    # ---- format 1: dimensions

    def _dim(self, node, fname: str):
        if node[0] != "name" or node[1] not in getattr(self.scope, "dims", {}):
            raise FormulaError(f"{fname}(): {node[1] if node[0] == 'name' else 'that'} is not a declared dimension")
        return self.scope.dims[node[1]]

    def _strides(self, dims) -> list[tuple[str, int]]:
        """(dimension, stride) for row-major storage: the last dimension varies fastest."""
        out, stride = [], 1
        for d in reversed(dims):
            out.append((d, stride))
            stride *= self.scope.dims[d].size
        return list(reversed(out))

    def _index(self, node, ctx: str | None) -> Built:
        _, name, coords = node
        sym = self.scope.symbols.get(name)
        if sym is None:
            raise FormulaError(f"unknown name {name!r}")
        dims = getattr(sym, "dims", ())
        if not dims:
            raise FormulaError(f"{name!r} has no dimensions to index")
        self.deps.add(name)
        fixed = []  # (dimension, position or None, closure, Dim), in the order written
        for dim, expr in coords:
            if dim not in dims:
                raise FormulaError(f"{name}[{dim}: ...]: {name} has no dimension {dim!r}")
            if any(f[0] == dim for f in fixed):
                raise FormulaError(f"{name}[...]: {dim} is fixed twice")
            D = self.scope.dims[dim]
            if D.kind == "list" and expr[0] == "name" and expr[1] in D.position:
                fixed.append((dim, D.position[expr[1]], None, D))
                continue
            b = self.build(expr, ctx)
            if b.type != "int":
                raise FormulaError(f"{name}[{dim}: ...]: a coordinate must be a whole number")
            if b.unit is not None:
                U.unify(b.unit, U.ONE, f"{name}[{dim}: ...] coordinate")
            fixed.append((dim, None, b.fn, D))
        named = {f[0] for f in fixed}
        missing = [d for d in dims if d not in named and d not in self.in_scope]
        if missing:
            raise FormulaError(f"{name}[...]: {missing[0]} is neither fixed nor in scope here")
        strides = dict(self._strides(dims))
        columns = self.rt.C

        def cell(i):
            positions = {}
            for dim, pos, f, D in fixed:
                if f is not None:
                    v = f(i)
                    pos = v - D.first if D.kind == "range" else v
                    if not 0 <= pos < D.size:
                        raise SimError(f"{name}[{dim}: {v}]: {dim} has no such member")
                positions[dim] = pos
            flat = 0
            for d in dims:
                flat += (positions[d] if d in positions else i[d]) * strides[d]
            return columns[name][flat]
        return Built(sym.type, sym.unit, cell)

    def _fn_sum(self, args, ctx):
        """Sum over the named dimensions, row-major in the order listed, into one total."""
        if len(args) < 2:
            raise FormulaError("sum() takes a value and at least one dimension")
        if ctx is not None:
            raise FormulaError(f"sum() is not available in a per-{ctx} formula")
        dims: list[str] = []
        for node in args[1:]:
            D = self._dim(node, "sum")
            if D.name in self.in_scope or D.name in dims:
                raise FormulaError(f"sum(): {D.name} is already in scope")
            dims.append(D.name)
        saved = self.in_scope
        self.in_scope = saved + tuple(dims)
        try:
            inner = self._number(self.build(args[0], ctx), "sum()")
        finally:
            self.in_scope = saved
        combos = list(itertools.product(*[range(self.scope.dims[d].size) for d in dims]))
        f = inner.fn

        def cells(i):
            base = dict(i) if isinstance(i, dict) else {}
            for combo in combos:
                for d, p in zip(dims, combo):
                    base[d] = p
                yield base

        if inner.type == "int":
            def fn(i):
                total = 0
                for c in cells(i):
                    total += f(c)
                return checked(total)
            return Built("int", inner.unit, fn)

        def fn_real(i):
            acc = 0.0
            for c in cells(i):
                acc = acc + f(c)
            return acc
        return Built("real", inner.unit, fn_real)

    def _fn_sum_by(self, args, ctx):
        """S10.3: sum_by(x, d, key, t): for each member of t (in scope), x summed over the
        cells of d whose key names that member (the member for a range, the position for a
        list), in ascending order of d. x and key are read with d in scope and t not; both are
        evaluated for every cell of d (strict evaluation), and a key that names no member of t
        is an error."""
        self._args("sum_by", args, 4)
        if ctx is not None:
            raise FormulaError(f"sum_by() is not available in a per-{ctx} formula")
        D = self._dim(args[1], "sum_by")
        T = self._dim(args[3], "sum_by")
        if T.name not in self.in_scope:
            raise FormulaError(f"sum_by(): {T.name} is not in scope here")
        if D.name in self.in_scope:
            raise FormulaError(f"sum_by(): {D.name} is already in scope")
        saved = self.in_scope
        self.in_scope = tuple(x for x in saved if x != T.name) + (D.name,)
        try:
            inner = self._number(self.build(args[0], ctx), "sum_by()")
            key = self.build(args[2], ctx)
        finally:
            self.in_scope = saved
        if key.type != "int":
            raise FormulaError("sum_by(): the key must be a whole number")
        if key.unit is not None:
            U.unify(key.unit, U.ONE, "sum_by() key")
        f, k, d, t, n = inner.fn, key.fn, D.name, T.name, D.size
        first = T.first if T.kind == "range" else 0
        whole = inner.type == "int"

        def fn(i):
            cell = {x: p for x, p in i.items() if x != t}
            total = 0 if whole else 0.0
            for j in range(n):
                cell[d] = j
                v, member = f(cell), k(cell)
                pos = member - first
                if not 0 <= pos < T.size:
                    raise SimError(f"sum_by(): a key {member} is not a member of {t}")
                if pos == i[t]:
                    total = total + v
            return checked(total) if whole else total
        return Built(inner.type, inner.unit, fn)

    def _fn_largest(self, args, ctx):
        """S10.3: the largest value over the named dimensions, row-major in the order listed:
        from the first cell, each later one taken if it is greater (as max())."""
        return self._extreme("largest", args, ctx, lambda y, x: y > x)

    def _fn_smallest(self, args, ctx):
        """S10.3: the smallest value over the named dimensions (as min(), folded)."""
        return self._extreme("smallest", args, ctx, lambda y, x: y < x)

    def _extreme(self, fname, args, ctx, better):
        if len(args) < 2:
            raise FormulaError(f"{fname}() takes a value and at least one dimension")
        if ctx is not None:
            raise FormulaError(f"{fname}() is not available in a per-{ctx} formula")
        dims: list[str] = []
        for node in args[1:]:
            D = self._dim(node, fname)
            if D.name in self.in_scope or D.name in dims:
                raise FormulaError(f"{fname}(): {D.name} is already in scope")
            dims.append(D.name)
        saved = self.in_scope
        self.in_scope = saved + tuple(dims)
        try:
            inner = self._number(self.build(args[0], ctx), f"{fname}()")
        finally:
            self.in_scope = saved
        combos = list(itertools.product(*[range(self.scope.dims[d].size) for d in dims]))
        f = inner.fn

        def fn(i):
            base = dict(i) if isinstance(i, dict) else {}
            best = None
            for combo in combos:
                for d, p in zip(dims, combo):
                    base[d] = p
                y = f(base)
                if best is None or better(y, best):
                    best = y
            return best
        return Built(inner.type, inner.unit, fn)

    def _fn_coord(self, args, ctx):
        self._args("coord", args, 1)
        D = self._dim(args[0], "coord")
        if D.name not in self.in_scope:
            raise FormulaError(f"coord({D.name}): {D.name} is not in scope here")
        name, first = D.name, (D.first if D.kind == "range" else 0)
        return Built("int", U.ONE, lambda i: first + i[name])

    def _fn_cohort_shift(self, args, ctx):
        self._args("cohort_shift", args, 2)
        D = self._dim(args[1], "cohort_shift")
        if D.name not in self.in_scope:
            raise FormulaError(f"cohort_shift(): {D.name} is not in scope here")
        inner = self._number(self.build(args[0], ctx), "cohort_shift()")
        f, n, dim, whole = inner.fn, D.size, D.name, inner.type == "int"
        zero = 0 if whole else 0.0

        def fn(i):
            p = i[dim]
            if n == 1:
                return f(i)
            if p == 0:
                return zero
            below = dict(i)
            below[dim] = p - 1
            if p == n - 1:
                a = f(below)
                b = f(i)
                return checked(a + b) if whole else a + b
            return f(below)
        return Built(inner.type, inner.unit, fn)

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

    def _fn_exp(self, args, ctx):
        """S5.1: e to the power x, by the fixed algorithm of docs/spec/02 (exp_fixed)."""
        self._args("exp", args, 1)
        a = self._number(self.build(args[0], ctx), "exp()")
        if a.unit is not None:
            U.unify(a.unit, U.ONE, "exp() argument")
        f = a.fn
        return Built("real", U.ONE, lambda i: exp_fixed(float(f(i))))

    def _unitless_real(self, name: str, args, ctx):
        """Stage S10.6: the arguments of ln, sqrt and pow: real or whole, unit 1, as reals."""
        fns = []
        for arg in args:
            a = self._number(self.build(arg, ctx), f"{name}()")
            if a.unit is not None:
                U.unify(a.unit, U.ONE, f"{name}() argument")
            fns.append(a.fn)
        return [lambda i, f=f: float(f(i)) for f in fns]

    def _fn_ln(self, args, ctx):
        """S10.6: the natural logarithm, by the fixed algorithm of docs/spec/02 (ln_fixed)."""
        self._args("ln", args, 1)
        (f,) = self._unitless_real("ln", args, ctx)
        return Built("real", U.ONE, lambda i: ln_fixed(f(i)))

    def _fn_sqrt(self, args, ctx):
        """S10.6: the square root, correctly rounded."""
        self._args("sqrt", args, 1)
        (f,) = self._unitless_real("sqrt", args, ctx)
        return Built("real", U.ONE, lambda i: sqrt_fixed(f(i)))

    def _fn_pow(self, args, ctx):
        """S10.6: x to the power y, as exp(y * ln(x)) by the fixed algorithms."""
        self._args("pow", args, 2)
        fx, fy = self._unitless_real("pow", args, ctx)
        return Built("real", U.ONE, lambda i: pow_fixed(fx(i), fy(i)))

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

    def _fn_div(self, args, ctx):
        """S10.3: div(a, b), whole numbers: a divided by b, rounded down; b must be positive."""
        return self._whole_division("div", args, ctx)

    def _fn_mod(self, args, ctx):
        """S10.3: mod(a, b), whole numbers: what is left of a after div(a, b) times b, from 0
        to b - 1; b must be positive and in a's unit."""
        return self._whole_division("mod", args, ctx)

    def _whole_division(self, fname, args, ctx):
        self._args(fname, args, 2)
        a, b = (self.build(x, ctx) for x in args)
        if not (a.type == b.type == "int"):
            raise FormulaError(f"{fname}() needs two whole numbers")
        if fname == "div":
            unit = U.div(a.unit, b.unit)
        else:
            unit = U.unify(a.unit, b.unit, "mod()")
        fa, fb = a.fn, b.fn

        def fn(i):
            x, y = fa(i), fb(i)
            if y <= 0:
                raise SimError(f"{fname}(): the divisor must be positive")
            return checked(x // y) if fname == "div" else x % y
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
        if self.in_scope:
            raise FormulaError("rand() is not available in a formula with dimensions")
        stream, rt = self.scope.streams[args[0][1]], self.rt
        if ctx is None:
            return Built("real", U.ONE, lambda i: uniform(rt.seed, stream, 0, rt.step))
        ids = self.scope.entities[ctx].ids
        return Built("real", U.ONE, lambda i: uniform(rt.seed, stream, ids[i], rt.step))

    def _weights(self, entity) -> list[int]:
        """The run's current weights of an entity: a list the simulation updates in place when
        a weight state changes (format 1, S4.4), so closures built now always see them."""
        return self.rt.W.get(entity.name, entity.weights)

    def _aggregate(self, fname: str, args, ctx):
        self._args(fname, args, 2)
        if ctx is not None:
            raise FormulaError(f"{fname}() cannot be used inside a per-{ctx} formula")
        if args[0][0] != "name" or args[0][1] not in self.scope.entities:
            raise FormulaError(f"{fname}(): the first argument must be the name of an entity")
        entity = self.scope.entities[args[0][1]]
        saved, self.in_scope = self.in_scope, ()  # a record's formula sees no dimensions
        try:
            return entity, self.build(args[1], entity.name)
        finally:
            self.in_scope = saved

    def _fn_wsum(self, args, ctx):
        """Weighted sum over all records. Whole numbers are summed exactly; reals are summed
        left to right in ascending record order, each term being real(weight) * value."""
        entity, inner = self._aggregate("wsum", args, ctx)
        self._number(inner, "wsum()")
        weights, count, f = self._weights(entity), len(entity.ids), inner.fn
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

    def _fn_quantile(self, args, ctx):
        """Stage S10.9: the value below which a share p of the records' weight lies. The
        records with a weight are ordered by value (ties by record order) and the result is
        the value of the first at which the weight so far reaches p times the total."""
        self._args("quantile", args, 3)
        if ctx is not None:
            raise FormulaError(f"quantile() cannot be used inside a per-{ctx} formula")
        if args[0][0] != "name" or args[0][1] not in self.scope.entities:
            raise FormulaError("quantile(): the first argument must be the name of an entity")
        entity = self.scope.entities[args[0][1]]
        saved, self.in_scope = self.in_scope, ()  # neither part sees the dimensions
        try:
            inner = self._number(self.build(args[1], entity.name), "quantile()")
            share = self._number(self.build(args[2], None), "quantile() share")
        finally:
            self.in_scope = saved
        if share.unit is not None:
            U.unify(share.unit, U.ONE, "quantile() share")
        weights, count, f, fp = self._weights(entity), len(entity.ids), inner.fn, share.fn

        def fn(i):
            values = [f(r) for r in range(count)]
            p = float(fp(i))
            if not 0.0 <= p <= 1.0:
                raise SimError("quantile(): the share must be from 0 to 1")
            if any(v != v for v in values):
                raise SimError("quantile(): a record's value is not a number")
            total = sum(weights)
            if total <= 0:
                raise SimError("quantile(): the records' weights add to nothing")
            target = p * float(total)
            so_far = 0
            for r in sorted((r for r in range(count) if weights[r] != 0), key=lambda r: (values[r], r)):
                so_far += weights[r]
                if float(so_far) >= target:
                    return values[r]
            raise SimError("quantile(): internal error")
        return Built(inner.type, inner.unit, fn)

    def _grouped(self, fname: str, args, ctx):
        """Format 1 (S4.0): wsum_by / wcount_by(entity, x, d, key)."""
        self._args(fname, args, 4)
        if ctx is not None:
            raise FormulaError(f"{fname}() cannot be used inside a per-{ctx} formula")
        if args[0][0] != "name" or args[0][1] not in self.scope.entities:
            raise FormulaError(f"{fname}(): the first argument must be the name of an entity")
        D = self._dim(args[2], fname)
        if D.name not in self.in_scope:
            raise FormulaError(f"{fname}(): {D.name} is not in scope here")
        entity = self.scope.entities[args[0][1]]
        saved, self.in_scope = self.in_scope, ()
        try:
            inner = self.build(args[1], entity.name)
            key = self.build(args[3], entity.name)
        finally:
            self.in_scope = saved
        if key.type != "int":
            raise FormulaError(f"{fname}(): the key must be a whole number")
        if key.unit is not None:
            U.unify(key.unit, U.ONE, f"{fname}() key")
        return entity, D, inner, key

    def _group_fn(self, fname, entity, D, inner, key, term):
        weights, count, f, k, dim = self._weights(entity), len(entity.ids), inner.fn, key.fn, D.name
        first = D.first if D.kind == "range" else 0

        def positions():
            out = []
            for r in range(count):
                v = k(r)
                pos = v - first
                if not 0 <= pos < D.size:
                    raise SimError(f"{fname}(): a record's key {v} is not a member of {dim}")
                out.append(pos)
            return out
        return weights, count, f, dim, positions

    def _per_member(self, totals_of):
        """The totals of every member at once, kept while one formula is being evaluated:
        records do not change in that time, so each cell's total is what a pass of its own
        would give (the same terms, in the same order), and the records are read once, not
        once per cell. `rt.generation` changes before every evaluation of a formula."""
        rt, cache = self.rt, {"generation": None, "totals": None}

        def lookup(p):
            if cache["generation"] != rt.generation or cache["generation"] is None:
                cache["totals"] = totals_of()
                cache["generation"] = rt.generation
            return cache["totals"][p]
        return lookup

    def _fn_wsum_by(self, args, ctx):
        """wsum over the records whose key is the current cell's member of a dimension."""
        entity, D, inner, key = self._grouped("wsum_by", args, ctx)
        self._number(inner, "wsum_by()")
        weights, count, f, dim, positions = self._group_fn("wsum_by", entity, D, inner, key, None)
        unit = U.mul(inner.unit, ((entity.name, 1),))
        if inner.type == "int":
            def totals():
                pos, out = positions(), [0] * D.size
                for r in range(count):
                    v = f(r)
                    out[pos[r]] += weights[r] * v
                return [checked(t) for t in out]
            lookup = self._per_member(totals)
            return Built("int", unit, lambda i: lookup(i[dim]))

        def totals_real():
            pos, out = positions(), [0.0] * D.size
            for r in range(count):
                v = f(r)
                out[pos[r]] = out[pos[r]] + float(weights[r]) * v
            return out
        lookup_real = self._per_member(totals_real)
        return Built("real", unit, lambda i: lookup_real(i[dim]))

    def _fn_wcount_by(self, args, ctx):
        entity, D, inner, key = self._grouped("wcount_by", args, ctx)
        self._boolean(inner, "wcount_by()")
        weights, count, f, dim, positions = self._group_fn("wcount_by", entity, D, inner, key, None)

        def totals():
            pos, out = positions(), [0] * D.size
            for r in range(count):
                if f(r):
                    out[pos[r]] += weights[r]
            return [checked(t) for t in out]
        lookup = self._per_member(totals)
        return Built("int", ((entity.name, 1),), lambda i: lookup(i[dim]))

    def _fn_wcount(self, args, ctx):
        entity, inner = self._aggregate("wcount", args, ctx)
        self._boolean(inner, "wcount()")
        weights, count, f = self._weights(entity), len(entity.ids), inner.fn

        def fn(_):
            total = 0
            for i in range(count):
                if f(i):
                    total += weights[i]
            return checked(total)
        return Built("int", ((entity.name, 1),), fn)


FUNCTIONS = sorted(name[4:] for name in dir(_Builder) if name.startswith("_fn_"))


def compile_formula(src: str, scope, rt, ctx: str | None, want_type: str,
                    want_unit: U.Unit, label: str, dims: tuple[str, ...] = ()):
    """Compile `src` for a target of the given type and unit.

    Returns (closure, names read this step, names read through prev()).
    A whole-number result may feed a real target; a real result never feeds a whole-number
    target without an explicit round(), floor() or ceil().
    """
    try:
        builder = _Builder(scope, rt, dims)
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
