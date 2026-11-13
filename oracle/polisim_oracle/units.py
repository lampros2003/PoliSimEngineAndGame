"""Unit algebra. A unit is a sorted tuple of (base name, integer exponent) pairs.

Examples: "GBP/month" -> (("GBP", 1), ("month", -1)); "1" -> ().
`None` stands for "any unit" and is used only for the literal zero.
"""

from __future__ import annotations

Unit = tuple[tuple[str, int], ...]
ONE: Unit = ()


class UnitError(Exception):
    pass


def parse_unit(text: str) -> Unit:
    """Parse "a*b/c^2". Operators apply left to right; "1" is dimensionless."""
    exponents: dict[str, int] = {}
    sign = 1
    token = ""

    def flush(tok: str, sgn: int) -> None:
        tok = tok.strip()
        if not tok:
            raise UnitError(f"malformed unit {text!r}")
        if tok == "1":
            return
        name, _, power = tok.partition("^")
        name = name.strip()
        if not name.replace("_", "a").isalnum() or name[0].isdigit():
            raise UnitError(f"bad unit name {name!r} in {text!r}")
        try:
            p = int(power) if power else 1
        except ValueError:
            raise UnitError(f"bad exponent in {text!r}") from None
        exponents[name] = exponents.get(name, 0) + sgn * p

    for ch in text:
        if ch in "*/":
            flush(token, sign)
            token = ""
            sign = 1 if ch == "*" else -1
        else:
            token += ch
    flush(token, sign)
    return tuple(sorted((k, v) for k, v in exponents.items() if v))


def _combine(a: Unit | None, b: Unit | None, sign: int) -> Unit:
    exponents = dict(a or ())
    for name, power in b or ():
        exponents[name] = exponents.get(name, 0) + sign * power
    return tuple(sorted((k, v) for k, v in exponents.items() if v))


def mul(a: Unit | None, b: Unit | None) -> Unit:
    return _combine(a, b, 1)


def div(a: Unit | None, b: Unit | None) -> Unit:
    return _combine(a, b, -1)


def unify(a: Unit | None, b: Unit | None, what: str) -> Unit | None:
    """Units of two operands that must agree. `None` (literal zero) adopts the other side."""
    if a is None:
        return b
    if b is None or a == b:
        return a
    raise UnitError(f"{what}: unit {fmt(a)} does not match {fmt(b)}")


def fmt(unit: Unit | None) -> str:
    if unit is None:
        return "any"
    if not unit:
        return "1"
    top = [n if p == 1 else f"{n}^{p}" for n, p in unit if p > 0]
    bottom = [n if p == -1 else f"{n}^{-p}" for n, p in unit if p < 0]
    return ("*".join(top) or "1") + "".join("/" + b for b in bottom)
