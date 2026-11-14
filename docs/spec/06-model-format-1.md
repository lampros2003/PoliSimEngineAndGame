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

## Weights that change (stage S4.4)

An entity's weights may be a record-level state instead of a data column, so that they
can change during a run: synthetic households kept in line with a population that ages.

```toml
[entity.household]
data = "households.csv"
id = "id"
weight = { state = "household_weight" }

[state.household_weight]
entity = "household"
type = "int"
unit = "1"
phase = "alignment"
initial = { column = "weight" }

[state.household_weight.rake]
when = "month_of_year == 0"
passes = 10

[[state.household_weight.rake.margin]]
target = "adults_in_households"   # dims = ["region", "sex", "adult_band"]
slots = [
  { count = "select(adults >= 1, 1, 0)", at = ["region_code", "sex1", "band_of_age[age: age1]"] },
  { count = "select(adults >= 2, 1, 0)", at = ["region_code", "sex2", "band_of_age[age: age2]"] },
]

[[state.household_weight.rake.margin]]
target = "households_by_region"   # dims = ["region"]
slots = [{ count = "1", at = ["region_code"] }]
```

**The weight state.** `weight = { state = "s" }` names a state of that entity, of type
`int`, unit `1` and no dimensions. Every value it holds, from its initial value on, must
be a whole number of at least 1 (a run-time error otherwise). Wherever records are
weighted (`wsum`, `wcount`, `wsum_by`, `wcount_by`, and the totals that explanations and
results give for record-level values), the weight is the state's value as a formula
would read it at that point: the start-of-step value until the phase that updates it has
committed, the new value after. No sector may hold its accounts record by record in an
entity whose weights change: a changed weight would create or destroy money. The state
has either a `next` formula, like any state, or a `rake`, and only a weight state may
have a `rake`.

**`rake`** sets the weights so that weighted totals of the records meet targets, by
iterative proportional updating. Its keys:

| Key | Meaning |
|---|---|
| `when` | A national formula, `bool`: the weights change only in steps where it is true |
| `passes` | A whole number from 1 to 1,000 |
| `margin` | One or more tables, each with `target` and `slots` |
| `target` | The name of a national param, var or state with dimensions, whole or real; a var must be computed in the state's phase or earlier |
| `slots` | One or more tables, each with `count` and `at` |
| `count` | A record formula, whole or real: how many of the target's units the record adds to one cell, per unit of weight |
| `at` | A list of record formulas, one per dimension of the target in its declared order, each a whole number without a unit: the record's member along that dimension (a range's member, or a list's position), as `wsum_by`'s key |

Every slot of a margin has counts of one unit `u`, and the target's unit is `u * entity`,
as for `wsum` of the count.

The rake is evaluated where the state's `next` formula would be (step 2.2 of the
[engine contract](00-engine-contract.md)), sees what such a formula sees, and its result
is committed with the phase's other states:

1. `when` is evaluated. If it is false, every weight stays as it is and nothing else of
   the rake is evaluated.
2. For each margin in order: every cell of the target must be finite and not negative
   (checked in row-major order); each slot's `count`, then its `at` formulas left to
   right, are evaluated for every record, strictly as record formulas always are; then,
   for each record in ascending order and each slot in order, the count must be finite
   and not negative and, if it is not zero, each `at` value must be a member of its
   dimension (left to right). The first failure is the error reported. A record and slot
   with a count that is not zero form a **pair** in the cell its `at` values name; an
   `at` value that goes with a zero count is not checked.
3. Each record starts from `v`, its current weight as a real. Then `passes` times, for each
   margin in order, for each cell of its target in row-major order: `S` is the sum,
   starting at real 0.0, of `v * real(count)` over the cell's pairs, records ascending and
   slots in order within a record, added one at a time; `T` is the target cell as a real.
   If `S > 0` and `T > 0`, then `f = T / S`, and every record with a pair in the cell,
   in ascending order, gets `v = v * f`, once however many of its slots are in the cell.
   Otherwise the cell is left alone.
4. The new weight of each record is `round(v)` (halves to the even neighbour), or 1 if
   that is less than 1. A `v` that is not finite, or rounds outside 64 bits, is an error.

Each pass brings each margin to its targets in turn, so after the last pass the last
margin fits exactly (before rounding) and the others more closely the more passes there
are; a cell with no pairs or a zero target cannot be met and is skipped. Only
multiplications and divisions are used, so every machine gives the same weights.

## Bills (stage S5.4)

A model may have a legislature that votes on the player's policy changes:

```toml
[legislature]
seats = "seats"            # a state of whole numbers with one dimension, the blocs
governing = "governing"    # a true/false state over the same dimension
position = "bloc_position" # a real parameter over the same dimension: left below zero

[lever.basic_rate]
leaning = "left"           # raising it moves policy to the left; "right" for the opposite
```

A lever's `leaning` is `"left"` or `"right"`; a true/false lever has none. In part 1 of a
step (engine contract, section 3), each lever change scheduled for the step is taken in
the order the commands list them (for one lever in one step the last command wins, in the
place of the first). If the model has a legislature, the lever has a leaning, and the
value the change would store differs from the lever's current value, the change is a
**bill** and is voted on:

1. The move is to the **left** if the value rises and the lever leans left, or falls and
   it leans right; otherwise it is to the right.
2. The **leader** is the governing bloc with the most seats (the first of the dimension on
   a tie); with no governing bloc there is none.
3. Policy is taken to stand at the leader's position (at zero with no leader). A bloc votes
   for the bill if it is the leader, or if the move is towards it: to the left and its
   position is lower than the leader's, or to the right and higher. The others vote
   against. Seats, governing and positions are read at their start-of-step values.
4. The bill **passes** if twice the seats of the blocs voting for it exceed the seats of
   all blocs (whole numbers, exactly). A bill that passes is applied, and its value then
   checked against the lever's range as any change is. A defeated bill changes nothing,
   is not range-checked, and is not an error.

Every vote is kept: the step, the lever, the value it would have stored, the seats for,
the seats of all blocs, and whether it passed. A model with a legislature adds the
result `bills_defeated` to each step's results: the number of bills defeated in it. A
saved game (version 2) keeps each policy change's vote.

So a government with a majority of its own passes every bill; without one, a move to
the left needs enough seats to the leader's left, and a move to the right enough to its
right.

## Load-time checks

Format 0's, plus: a dimension used but not declared; `dims` on an element that cannot
have them, or with a repeat; a list member named like an element; a data file with a
missing, repeated or unknown cell, or a missing column; a dimensioned value read with a
dimension out of scope; `sum` over a dimension already in scope or not declared;
`coord` or `cohort_shift` of a dimension not in scope; an index on something without
that dimension, or the same dimension indexed twice. For weights that change: a weight
state that is not an `int` state of unit `1`, without dimensions, of its own entity; a
sector held record by record in that entity; a state with both `next` and `rake`, or a
`rake` on a state that is not a weight state; a `rake` whose `passes` is not a whole
number from 1 to 1,000, with no margin or a margin with no slot, whose target is not a
national param, var or state with dimensions, or is a var computed in a later phase;
`at` with the wrong number of formulas; counts of different units in one margin, or of
a unit that does not match the target's. For bills: a `leaning` other than `"left"` or
`"right"`, or on a true/false lever; a `[legislature]` in format 0, without exactly the
keys `seats`, `governing` and `position`, naming something that is not a whole-number
state, a true/false state and a real parameter respectively, each with one dimension, or
with different dimensions.

## Not in format 1

Dimensioned levers, flows and accounts (a regional budget is a dimensioned var summed
into a national flow); dimensions on record-level elements; random draws per cell; weights
that are not whole numbers, and calibration methods other than the rake (such as
exponential calibration, which needs `exp`); interpolation between members; reductions
other than `sum` (means and shares are written with `sum` and `/`).

## Test model

`models/cohort/` (written by `tools/make_cohort.py`) uses every feature above: a
population by region, sex and age with births, deaths, migration and monthly ageing; an
integer state on a range starting at 16; a parameter with a column per preset; a
dimensioned var read through `prev()`; and records that look a rate up by region.
`oracle/tests/test_format1.py` tests the rules; `models/cohort/golden/` holds the
oracle's state hashes, which the engine must reproduce.

`models/raking/` (written by `tools/make_raking.py`) tests weights that change: 2,000
invented households raked once a year to three margins (adults by region, sex and age
band, three slots per household; children by region; households by size, a whole-number
target on a range dimension), with aggregates before and after the rake. The hand-worked
cases of `conformance/rake_cases.toml` (the rake's arithmetic, its skips and rounding, and
every refusal and run-time error above) are run by both `oracle/tests/test_raking.py` and
`crates/core/tests/raking.rs`. Likewise `conformance/bill_cases.toml` for bills, run by
`oracle/tests/test_bills.py` and `crates/core/tests/bills.rs`.
