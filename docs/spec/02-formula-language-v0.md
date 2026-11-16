# Formula language 0

Formulas are pure expressions: no assignment, no loops, no side effects. Each one
computes a single value, either for the nation or for one record of an entity. The
engine implements the language in `crates/core/src/syntax.rs`, `compile.rs` and `vm.rs`;
`conformance/cases.tsv` and `format1.tsv` pin the result of each listed formula.

Related: [engine contract](00-engine-contract.md), [model format](01-model-format-v0.md).

## Grammar

```
expr     := conj ( "or" conj )*
conj     := neg ( "and" neg )*
neg      := "not" neg | compare
compare  := sum ( ( "<" | "<=" | ">" | ">=" | "==" | "!=" ) sum )?
sum      := product ( ( "+" | "-" ) product )*
product  := unary ( ( "*" | "/" ) unary )*
unary    := "-" unary | primary
primary  := NUMBER | "true" | "false" | NAME | NAME "(" args ")" | "(" expr ")"
args     := ( expr ( "," expr )* )?
```

A number with a decimal point or exponent is a real (`0.2`, `1e-3`); otherwise it is a
whole number (`4000`, `1_000_000`). Comparisons do not chain: `a < b < c` is an error.

## Types

| Expression | Result |
|---|---|
| whole `+ - *` whole | whole number; overflow is an error |
| any mix with a real, for `+ - *` | real; the whole number is converted first |
| anything `/` anything | real, always |
| comparison | true/false; a whole number compared with a real is converted first |
| `and`, `or`, `not` | true/false, from true/false operands only |

A formula whose result is a whole number may feed a `real` variable. A formula whose
result is a real may **not** feed a `money` or `int` variable: wrap it in `round`,
`floor` or `ceil`. The rounding is always visible in the model text.

Real division follows IEEE 754: dividing by zero gives an infinity or not-a-number
inside the formula, which is harmless if it is then discarded and an error if it is
stored or rounded.

## Units

Every value carries a unit, and the checker enforces:

- `+`, `-`, comparisons, `min`, `max`, `clamp`, `select`: both sides must have the same unit;
- `*` and `/` multiply and divide units;
- a formula's unit must equal its variable's declared unit;
- number literals are dimensionless, **except zero**, which fits any unit. So
  `max(income, 0)` is fine and `income + 100` is an error: a constant with a unit has to
  be a parameter, which gives it a name, a unit and a place in the documentation.

## Scope

A national formula can name parameters, levers and national variables, flows, states and
accounts. It reaches record-level values only through `wsum` and `wcount`.

A record-level formula (one declared with `entity`) can name all of the above, which
take the same value for every record, plus the columns, variables, flows, states and
accounts of its own entity, which take that record's value.

## Functions

| Function | Result | Definition |
|---|---|---|
| `min(a, b)` | number | `b` if `b < a`, else `a` |
| `max(a, b)` | number | `b` if `b > a`, else `a` |
| `clamp(x, lo, hi)` | number | `min(max(x, lo), hi)` |
| `abs(x)` | number | magnitude; overflow is an error for the most negative whole number |
| `exp(x)` | real | e to the power `x`, by the fixed algorithm below; `x` real or whole, unit 1 (added in stage S5.1) |
| `ln(x)` | real | the natural logarithm, by the fixed algorithm below; `x` real or whole, unit 1; not-a-number below zero, minus infinity at zero (added in stage S10.6) |
| `sqrt(x)` | real | the square root, correctly rounded (IEEE 754); `x` real or whole, unit 1; not-a-number below zero (added in stage S10.6) |
| `pow(x, y)` | real | `x` to the power `y`, by the algorithm below; both real or whole, unit 1 (added in stage S10.6) |
| `round(x)` | whole | nearest whole number, halves to the even neighbour |
| `floor(x)`, `ceil(x)` | whole | toward minus / plus infinity |
| `select(c, a, b)` | as `a`, `b` | `a` where `c` is true, else `b` |
| `safe_div(a, b, d)` | real | `d` where `b` is zero, else `real(a) / real(b)` |
| `muldiv(a, b, c)` | whole | `floor(a * b / c)` computed exactly; `c` must be positive |
| `div(a, b)` | whole | `floor(a / b)` for whole numbers; `b` must be positive (a run-time error otherwise); unit `unit(a) / unit(b)` (added in stage S10.3) |
| `mod(a, b)` | whole | `a - b * div(a, b)`, from 0 to `b - 1`; `b` must be positive; `a` and `b` in one unit, the result's (added in stage S10.3) |
| `marginal(x, table)` | whole | marginal-rate schedule, below |
| `curve(x, table)` | real | an effect curve's value at `x`, below; `x` real or whole, in the curve's `x_unit`; the result in its `unit` (added in stage S11.1) |
| `per_step(x)` | as `x` | same value; unit divided by the step unit (a stock made comparable with a flow) |
| `times_step(x)` | as `x` | same value; unit multiplied by the step unit |
| `prev(name)` | as `name` | the value at the end of the previous step |
| `rand(stream)` | real | a draw in [0, 1) for this record and step from the named stream |
| `wsum(entity, x)` | as `x` | sum over records of `weight * x`; national formulas only |
| `wcount(entity, c)` | whole | sum of the weights of records where `c` is true |
| `quantile(entity, x, p)`, `quantile(entity, x, p, n)` | as `x` | the value below which a share `p` of the records' weight lies, below; with `n`, each record counts `n` times its weight; not in per-record formulas (added in stages S10.9 and S11.2) |

`round`, `floor` and `ceil` of an infinity, a not-a-number or a value outside the 64-bit
range are errors. `min`, `max` and `clamp` return a whole number only when every argument
is one. `wsum` has unit `unit(x) * entity`; `wcount` has unit `entity`.

All arguments are always evaluated (see the engine contract, section 7). In particular
`select(d != 0, round(x / d), 0)` is an error when `d` is zero, because the rounding
still happens; write `round(safe_div(x, d, 0.0))`.

### `exp(x)`

So that every machine gives the same bits, `exp` is computed by this algorithm, not by a
library: real arithmetic as in section 1 of the engine contract (each `+`, `-`, `*` rounded
once, no fused multiply-add). A whole-number `x` is first converted to a real.

```
if x is not a number:  result is x
if x > 709.0:          result is +infinity
if x < -708.0:         result is 0.0
k = round(x * 1.4426950408889634)             (halves to the even neighbour)
r = (x - k * 0.6931471803691238) - k * 1.9082149292705877e-10
p = 1.6059043836821613e-10
for c in 2.08767569878681e-09, 2.505210838544172e-08, 2.755731922398589e-07,
         2.7557319223985893e-06, 2.48015873015873e-05, 0.0001984126984126984,
         0.001388888888888889, 0.008333333333333333, 0.041666666666666664,
         0.16666666666666666, 0.5, 1.0, 1.0:
    p = p * r + c
result is p * 2^k                             (exact: 2^k is a power of two in range)
```

The constants are the nearest doubles to 1/ln 2, ln 2 split into a high part with
trailing zeros and the rest, and 1/n! for n = 13 down to 0. Over the range the result is
within 2 units in the last place of the true value (tested against the C library).

### `ln(x)`

As for `exp`: real arithmetic as in section 1 of the engine contract (each `+`, `-`, `*`,
`/` rounded once, no fused multiply-add), a whole-number `x` first converted to a real.

```
if x is not a number or x < 0:  result is not-a-number
if x is zero (either sign):     result is -infinity
if x is +infinity:              result is +infinity
(m, e) = the fraction and exponent of x: x = m * 2^e, 0.5 <= m < 1   (exact)
if m < 0.7071067811865476:  m = m * 2, e = e - 1                       (exact)
f = m - 1.0                                                            (exact)
s = f / (2.0 + f)
z = s * s
w = z * z
R = z * (L1 + w * (L3 + w * (L5 + w * L7))) + w * (L2 + w * (L4 + w * L6))
h = 0.5 * f * f
k = e as a real
result is k * 0.6931471803691238 - ((h - (s * (h + R) + k * 1.9082149292705877e-10)) - f)
```

with L1 = 0.6666666666666735, L2 = 0.3999999999940942,
L3 = 0.2857142874366239, L4 = 0.22222198432149784,
L5 = 0.1818357216161805, L6 = 0.15313837699209373 and
L7 = 0.14798198605116586, the coefficients of the widely used fdlibm logarithm, and
ln 2 split in two as for `exp`. Over the range the result is within 1 unit in the last
place of the true value (tested against the C library on two million values).

### `pow(x, y)`

```
if y is not a number:                    result is not-a-number
if y is whole and -1024 <= y <= 1024:     by repeated squaring:
    n = |y|, r = 1.0, b = x
    while n > 0:
        if n is odd: r = r * b
        n = n div 2
        b = b * b
    result is r if y >= 0, else 1.0 / r   (1.0 / 0 is an infinity of the zero's sign)
otherwise:
    if x is not a number or x < 0:  result is not-a-number
    if x is zero:                   result is 0.0 if y > 0, else +infinity
    if x is +infinity:              result is +infinity if y > 0, else 0.0
    result is exp(y * ln(x))        (the fixed algorithms above)
```

So `pow(5, 2)` is exactly 25, a negative `x` has whole powers, and `pow(x, 0)` is 1 for any
`x`. Otherwise the result is within about `|y * ln(x)|` units in the last place (the error
of the product, which `exp` magnifies): the same bits everywhere, but not the closest
double. For a square root write `sqrt`, which is.

### `curve(x, table)`

The table is a curve (`docs/spec/01-model-format-v0.md`). Its points' coordinates are
national formulas, evaluated as reals; a whole-number `x` is converted to a real.

```
the points' x must be strictly ascending, else an error
if x is not a number:   result is x
if x <= x_0:            result is y_0
if x >= x_last:         result is y_last
else, for the k with x_k <= x < x_(k+1):
    result is y_k + (y_(k+1) - y_k) * ((x - x_k) / (x_(k+1) - x_k))
```

### `quantile(entity, x, p)`

`x` is a per-record number (whole or real, any unit: the result has its type and unit); `p`
is a national number of unit 1, the share, taken as a real. Like `wsum`, it may be used in
national formulas and in formulas with dimensions, which it ignores. In this order:

```
x is evaluated for every record, in record order (the first error stops it)
n, if given, is evaluated for every record in the same way; else n is 1
p is evaluated
p must be from 0.0 to 1.0, else an error (not-a-number is an error)
no record's x may be not-a-number, else an error
no record's n may be below 0, else an error
each[r] = weight[r] * n[r], exactly; W = the sum of each[r]; W must be above 0, else an error
the records whose each[r] is not 0, ordered by x ascending, ties by record order
    (-0.0 and 0.0 tie)
so_far = 0; for each record r in that order:
    so_far = so_far + each[r]
    if real(so_far) >= p * real(W): result is x[r]
```

`n` is a per-record whole number of unit 1 (stage S11.2): with the number of people in
each household, `quantile(household, equivalised_income, 0.5, people)` is the median
person's household income, as poverty statistics count it. So
`quantile(household, net_income, 0.5)` is the weighted median household, `p = 0` gives the
smallest value with a weight and `p = 1` the largest. The result is always one record's
value, never an average of two.

### `marginal(x, table)`

`x` is a whole number of money and must have the table's unit. With bands
`(from_0, rate_0), (from_1, rate_1), ...` in ascending order:

```
acc = 0.0
for each band k, in order:
    upper = from_(k+1), or unbounded for the last band
    part  = the amount of x that lies between from_k and upper   (whole number, never negative)
    acc   = acc + rate_k * real(part)
result = round(acc)
```

Money below the first `from` is in no band. Thresholds that descend are an error.

## Not in format 0

Moving averages. They will be added when
a model needs them, with a definition as exact as the ones above. Since this list was
written, `exp` (stage S5.1), `ln`, `sqrt` and `pow` (S10.6), `quantile` (S10.9) and
`curve` (S11.1, lookup tables with interpolation) have joined the language,
format 1 has added sums over dimensions (`docs/spec/06-model-format-1.md`), and lags
longer than one step are a section of their own (`[lag]`, S10.5).
