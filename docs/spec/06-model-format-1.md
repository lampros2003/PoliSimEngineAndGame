# Model-file format 1: dimensions

Format 1 is format 0 ([model format](01-model-format-v0.md), [formula
language](02-formula-language-v0.md)) plus **dimensions**: named, ordered sets such as
age, sex, region or industry, over which a parameter, variable or state holds one value
per cell. It is what the cohort population table and the industries of stage S3.6 need,
and what households of stage S4 will look values up in. Everything in format 0 keeps its
meaning; a model opts in with `format = 1`.

The oracle (`oracle/polisim_oracle/`) defines the behaviour and the engine must match it
bit for bit, so every operation below states its order of evaluation.

## Declaring a dimension

```toml
[dim.age]
range = [0, 100]          # members 0, 1, ..., 100, in that order

[dim.sex]
members = ["female", "male"]

[dim.region]
members = ["north_east", "north_west", "yorkshire", "east_midlands"]
labels = ["North East", "North West", "Yorkshire and The Humber", "East Midlands"]
```

A dimension is either a **range** of whole numbers (`range = [first, last]`, `first <=
last`) or a **list** of member names (`members`, each a valid name, no repeats). Members
are ordered; a member's **position** counts from 0. `labels` are optional names for
people. A list member may not have the name of any declared element, so that `x[sex:
female]` can never mean two things. A dimension has at least one member and at most
1,000,000; a value's cells (the product of its dimensions' sizes) number at most
16,777,216.

## Dimensioned elements

`param`, `var` and `state` take an optional `dims`, a list of dimension names without
repeats: `dims = ["sex", "age"]`. The element holds one value per cell, every cell of the
same type and unit. Cells are stored, hashed and written in **row-major order** of the
declared list: the last dimension varies fastest. An element with `dims` may not also
have an `entity`; levers, flows and accounts have no `dims` in format 1.

A dimensioned **parameter** gives its values in one of two ways:

- `value = 0.012` (or the presets `low`, `central`, `high`): the same value in every cell;
- `data = "data/mortality.csv"`: a CSV file with one column per dimension, named after
  it, holding the member (the number for a range dimension, the name for a list one), and
  a value column, named by `column` (default `"value"`). `columns = { low = "lo",
  central = "mid", high = "hi" }` names one value column per preset instead. Every cell
  must appear exactly once; a missing, repeated or unknown cell is a load-time error.

A dimensioned **state** gives `initial` as a single number (every cell) or as `{ data =
"...", column = "..." }` in the same CSV form. A dimensioned **var** that is read through
`prev()` gives `initial` the same way.

The model hash covers these data files too: after the entities' files, each data file of
a dimensioned element once, in ascending order of its path as written (compared as UTF-8
bytes), each preceded by that path as in format 0.

## Formulas over cells

The formula of a dimensioned var or state is evaluated once per cell. Inside it, the
element's dimensions are **in scope**, and the formula sees the coordinates of the cell
being computed:

- a value without dimensions is the same in every cell;
- a dimensioned value whose dimensions are all in scope is read at the current cell's
  coordinates for those dimensions, whatever their order in its declaration: in a formula
  for `deaths` with `dims = ["region", "sex", "age"]`, `mortality` with `dims = ["sex",
  "age"]` is read at this cell's sex and age;
- reading a dimensioned value with a dimension that is not in scope is a load-time
  error: reduce it with `sum`, or fix that dimension with an index.

A formula without `dims` (and every format 0 formula) has nothing in scope.

### Indexing

`x[d: e]` reads `x` with dimension `d` fixed; several may be given, `x[sex: female,
age: 0]`. `x` must be the name of a dimensioned element and `d` one of its dimensions,
each at most once. The coordinate `e` is:

- for a range dimension, a whole-number expression giving the **member**: `pop[age: 65]`,
  `pop[age: coord(age) - 1]`;
- for a list dimension, a member name (`[sex: female]`), or a whole-number expression
  giving the **position**.

A coordinate outside the dimension is a run-time error. The remaining dimensions of `x`
must be in scope. The coordinate expressions are evaluated in the scope of the
surrounding formula, in the order written, before `x` is read; a coordinate must be a
whole number without a unit. Indexing works in record-level formulas too, so a
household can look up a rate by its region column: `rate_by_region[region: region_code]`.

### Functions

| Function | Result | Definition |
|---|---|---|
| `sum(x, d1, d2, ...)` | as `x` | sum of `x` over every combination of members of the named dimensions |
| `coord(d)` | whole | the current cell's member along `d` (range dimension) or its position (list dimension) |
| `cohort_shift(x, d)` | as `x` | `x` moved one member up along `d`; below |
| `wsum_by(entity, x, d, key)` | as `x` | `wsum` over the records whose `key` is the current cell's member of `d`; below |
| `wcount_by(entity, c, d, key)` | whole | `wcount` over the records whose `key` is the current cell's member of `d` |

**`sum`.** The named dimensions must not already be in scope; they are in scope inside
`x`, along with the surrounding formula's. The terms are taken in row-major order of the
dimensions **as listed in the call** (the last listed varies fastest), each combination
once, and accumulated one at a time into a single total that starts at whole-number 0
when `x` is a whole number and at real 0.0 when it is a real: `total = total + term`.
Whole numbers are summed exactly and the total must fit in 64 bits (as with `wsum`, only
the total is checked); reals are added in exactly that order. The unit is the unit of
`x`.

**`cohort_shift(x, d)`**, for `d` in scope: at the first member of `d` the result is zero
(whole 0 or real 0.0, as `x`); at a member strictly between the first and the last it is
`x` at the member below; at the last member it is `x` at the member below plus `x` at the
last member (an open top group: whoever is in it stays in it). With one member the result
is `x` itself. Everything else about the cell is unchanged. It is the ageing step of a
cohort table: one year of ageing at monthly steps, with birthdays spread through the year,
is

```toml
[state.population]
dims = ["region", "sex", "age"]
next = "population - deaths + migration - ageing_share * population + ageing_share * cohort_shift(population, age) + select(coord(age) == 0, births, 0.0)"
```

where `ageing_share` is 1/12 a month.

**`wsum_by` and `wcount_by`** (added in stage S4.0) total records by a dimension, such
as tax paid by households in each region. `d` must be in scope; `x` (or the condition
`c`) and `key` are record-level formulas, and `key` is a whole number without a unit
giving each record's member of `d` (a range's member, or a list's position). In the cell
whose coordinate along `d` is `p`, the result is the `wsum` (or `wcount`) of the records
whose key is `p`: every record's `x` and key are evaluated, and the terms of the matching
records are taken in ascending record order, as in `wsum`. A record whose key is not a
member of `d` is a run-time error. The unit is `unit(x) * entity` (`entity` for
`wcount_by`). Writing `x` as a dimensioned var with `dims = [d]` gives the totals by
member; their `sum` over `d` equals the `wsum` of all records, up to rounding of reals.

### Where the new functions work

`sum`, `coord`, `cohort_shift`, `wsum_by` and `wcount_by` work in national and dimensioned
formulas, not in record-level ones (a record reaches a dimensioned value only by indexing every dimension).
`rand` does not work in a dimensioned formula. The inner formula of `wsum` and `wcount`
is a record's formula and sees no dimensions, even inside a dimensioned formula.

### Evaluation order

Within one cell, a formula is evaluated as in format 0: every argument, left to right.
The cells of one element are computed in row-major order of its declared dimensions.
Since a formula cannot read its own element's current value, the order of cells changes
no result; it fixes where an error is reported (the first failing cell in that order).

## Results

The command-line runner writes national values as in format 0. A dimensioned element is
not written cell by cell; write a national var with `sum(...)` for any total a run should
report. Its cells are part of the state hash, in row-major order, like a record-level
column.

## Load-time checks

Format 0's, plus: a dimension used but not declared; `dims` on an element that cannot
have them, or with a repeat; a list member named like an element; a data file with a
missing, repeated or unknown cell, or a missing column; a dimensioned value read with a
dimension out of scope; `sum` over a dimension already in scope or not declared;
`coord` or `cohort_shift` of a dimension not in scope; an index on something without
that dimension, or the same dimension indexed twice.

## Not in format 1

Dimensioned levers, flows and accounts (a regional budget is a dimensioned var summed
into a national flow); dimensions on record-level elements; random draws per cell; record weights that change
during a run (planned for stage S4.4); interpolation between
members; reductions other than `sum` (means and shares are written with `sum` and `/`).

## Test model

`models/cohort/` (written by `tools/make_cohort.py`) uses every feature above: a
population by region, sex and age with births, deaths, migration and monthly ageing; an
integer state on a range starting at 16; a parameter with a column per preset; a
dimensioned var read through `prev()`; and records that look a rate up by region.
`oracle/tests/test_format1.py` tests the rules; `models/cohort/golden/` holds the
oracle's state hashes, which the engine must reproduce.
