# Formula language 0

Formulas are pure expressions: no assignment, no loops, no side effects. Each one
computes a single value, either for the nation or for one record of an entity. The
implementation that defines the language is `oracle/polisim_oracle/expr.py`.

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
| `round(x)` | whole | nearest whole number, halves to the even neighbour |
| `floor(x)`, `ceil(x)` | whole | toward minus / plus infinity |
| `select(c, a, b)` | as `a`, `b` | `a` where `c` is true, else `b` |
| `safe_div(a, b, d)` | real | `d` where `b` is zero, else `real(a) / real(b)` |
| `muldiv(a, b, c)` | whole | `floor(a * b / c)` computed exactly; `c` must be positive |
| `marginal(x, table)` | whole | marginal-rate schedule, below |
| `per_step(x)` | as `x` | same value; unit divided by the step unit (a stock made comparable with a flow) |
| `times_step(x)` | as `x` | same value; unit multiplied by the step unit |
| `prev(name)` | as `name` | the value at the end of the previous step |
| `rand(stream)` | real | a draw in [0, 1) for this record and step from the named stream |
| `wsum(entity, x)` | as `x` | sum over records of `weight * x`; national formulas only |
| `wcount(entity, c)` | whole | sum of the weights of records where `c` is true |

`round`, `floor` and `ceil` of an infinity, a not-a-number or a value outside the 64-bit
range are errors. `min`, `max` and `clamp` return a whole number only when every argument
is one. `wsum` has unit `unit(x) * entity`; `wcount` has unit `entity`.

All arguments are always evaluated (see the engine contract, section 7). In particular
`select(d != 0, round(x / d), 0)` is an error when `d` is zero, because the rounding
still happens; write `round(safe_div(x, d, 0.0))`.

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

Powers, logarithms, exponentials and square roots (they need the engine's own
implementations to stay reproducible); lags longer than one step; moving averages;
lookup tables with interpolation; sums over dimensions; quantiles. Each will be added
when a model needs it, with a definition as exact as the ones above.
