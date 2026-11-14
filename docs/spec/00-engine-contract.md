# Engine contract (v0)

What any implementation of the simulation must do. The Python oracle in `oracle/` is this
document in executable form; where the two disagree, the oracle is right and this
document has a bug. The Rust engine is correct when it reproduces the oracle's state hash
on every step of every scenario.

Related: [model format](01-model-format-v0.md), [formula language](02-formula-language-v0.md),
[toy model](03-toy-model.md).

## 1. Values

There are three kinds of value.

| Kind | Representation | Used for |
|---|---|---|
| whole number | signed 64-bit integer | money (in minor units, such as pence), head-counts, weights, codes |
| real | IEEE 754 binary64 | rates, shares, probabilities, opinions |
| true/false | boolean | status flags, conditions |

Rules that follow from the choice:

- **Money and head-counts are whole numbers**, so every total is exact and does not
  depend on the order of addition or on the number of threads.
- **A whole-number result that does not fit in 64 bits is an error.** It is never
  wrapped or saturated.
- **A real that is infinite or not-a-number may exist inside a formula but may not be
  stored.** Storing one into any variable is an error.
- **Real arithmetic is IEEE 754 with round-to-nearest-even**: `+`, `-`, `*`, `/` only,
  each operation rounded once. No fused multiply-add, no reassociation, no fast-math.
- **Nothing calls the platform maths library.** Format 0 has no transcendental functions.
  When they are added the engine will carry its own implementation.
- **Converting a whole number to a real** rounds to nearest-even (exact below 2^53).
  **Converting a real to a whole number** is always explicit: `round` (half to even),
  `floor` or `ceil`.

## 2. State

A run's persistent state is:

- the step counter;
- the current setting of every **lever**;
- the balance of every **account** (one whole number per sector, or one per record for a
  sector whose accounts are held record by record);
- the value of every **state** variable;
- the last computed value of every `var` or `flow` that some formula reads through `prev()`.

Everything else is recomputed each step. Parameters and data columns never change during
a run.

## 3. One step

Steps are numbered from 0. Step `t` does the following, in this order.

1. **Commands.** Apply the lever changes scheduled for step `t`. A value outside the
   lever's declared range is an error.
2. **Phases**, in the order the model declares them. For each phase:
   1. evaluate every `var` and `flow` of the phase, in dependency order;
   2. evaluate the `next` formula of every `state` updated in the phase;
   3. commit those new state values together.
3. **Posting.** Apply every flow to the accounts (section 4).
4. **Checks.** Verify declared ranges and the accounting identities (section 5).
5. **Remember.** Keep the values `prev()` will need. The state hash now describes the end
   of step `t`.

What a formula sees while step `t` runs:

| It names | It gets |
|---|---|
| a parameter, lever or data column | the current value |
| a `var` or `flow` in the same or an earlier phase | the value computed this step |
| a `var` or `flow` in a later phase | nothing: this is a load-time error |
| an account | the balance at the start of the step, in every phase |
| a state | the new value in phases after the one that updates it, otherwise the start-of-step value |
| `prev(x)` | the value `x` had at the end of step `t - 1`; in step 0, its declared `initial` |

Consequences: there is no solver inside a step; a dependency cycle within a step is a
load-time error and is broken by `prev()`; and because formulas are pure, the order in
which independent formulas are evaluated cannot change a result.

## 4. Flows and accounts

Every movement of money is a **flow** from one sector to another through an
**instrument**. Posting a flow of amount `a` subtracts `a` from the payer's account in
that instrument and adds `a` to the receiver's. An instrument is a claim on its issuer,
so the issuer's balance is the negative of everything the other sectors hold.

- A flow amount must be zero or positive. A negative amount is an error.
- A flow between two sectors with one account each has a single amount.
- A flow touching a sector whose accounts are held record by record has one amount per
  record. Record `i` stands for `weight[i]` identical real units, so its own balance
  moves by `amount[i]` and the other sector's account moves by the sum of
  `weight[i] * amount[i]`. Weights are positive whole numbers, so the sum is exact.
- All flows of a step are posted together after the last phase, in the order the model
  declares them. A flow's total, and every balance after each flow is applied, must fit
  in 64 bits.

## 5. Identities checked every step

1. For every account, the change in its (weighted) total equals the sum of the flows in
   minus the sum of the flows out.
2. For every instrument, the balances of all sectors sum to exactly zero.

Both hold by construction in the oracle. They are stated because the engine will compute
the same totals by a different route (blocks, later threads), and these are the tests
that route must pass.

## 6. Random numbers

A random draw is a pure function `uniform(seed, stream, entity, step)`:

- the generator is Philox4x32 with 10 rounds;
- counter = (entity low 32 bits, entity high 32 bits, step, stream); key = (seed low 32
  bits, seed high 32 bits);
- the first two output words form a 64-bit number (first word high); its top 53 bits
  times 2^-53 is the result, a real in [0, 1);
- `stream` is the 32-bit FNV-1a hash of the stream's name in UTF-8;
- `entity` is the record's id (not its position), and 0 in a national formula.

There is no generator state. A draw does not depend on evaluation order, on other draws,
or on how many records exist. Two runs with one seed therefore share every draw until a
policy difference changes what the draws are compared against.

## 7. Evaluation is strict

Every argument of every function is evaluated, including both branches of `select` and
both sides of `and` and `or`. An error anywhere in a formula is an error whichever branch
is taken. This lets the engine evaluate a formula over a block of records one operation
at a time without tracking which records took which branch.

## 8. Reductions

- A weighted sum of whole numbers is exact; any order gives the same answer. The result
  must fit in 64 bits.
- A weighted sum of reals is computed in ascending record order: `acc = 0.0`, then
  `acc = acc + real(weight[i]) * value[i]` for each record in turn.

The second rule forbids vectorised or threaded real sums. It is acceptable because totals
that matter are whole numbers. If profiling shows real sums matter, a fixed blocked order
will replace it in a later format version.

Since stage S4.4 the engine evaluates a record-level formula over large entities on
several threads, each thread taking whole blocks of records; records are independent, so
every value is what one thread would compute, the parts are joined in record order, and
the error reported is the first in record order. Sums still run in record order on one
thread.

## 9. State hash

SHA-256 over the following bytes:

1. the 13 bytes `PSIM-STATE-v0` followed by a zero byte;
2. the number of completed steps as an unsigned 64-bit little-endian integer;
3. for each lever, account, state and `prev()`-read `var` or `flow`, in ascending order of
   name (byte order): the name in UTF-8, a zero byte, then its value, or its values in
   record order.

Value encoding: whole numbers as 8 bytes little-endian two's complement; reals as the 8
bytes of their IEEE 754 pattern, little-endian; true/false as one byte, 1 or 0.

The hash is taken at the end of every step. Two implementations agree when their hashes
agree at every step, which is a far stricter test than agreeing at the end.

## 10. Errors

An error stops the run and names the step and the variable. There is no recovery inside
the engine: a model that divides by zero into a stored value, overflows, leaves a
declared range, posts a negative flow or breaks an identity is a wrong model, and the
earlier it stops the cheaper the fix.

## 11. Not in v0

Command logs; mods and patches; threads; lags longer than one step; moving averages;
dimensions other than one entity (regions, industries); native operators (cohort ageing,
alignment, seat allocation); transcendental functions. Each is planned; none is needed by
the toy model. Snapshot saves exist and are described in [save format 0](04-save-format-v0.md).

## 12. Two implementations

| | Oracle (`oracle/`) | Engine (`crates/core/`) |
|---|---|---|
| Language | Python | Rust |
| Purpose | defines the behaviour | runs the game |
| Formulas | closures, one record at a time | register bytecode, a block of records at a time |
| Speed at 1,000 households | about 17 ms per step | about 0.2 ms per step |

They are held together by three tests. `conformance/cases.tsv` lists formulas with the
result the oracle gives for each, and both sides check every line. The engine must
reproduce the oracle's recorded hash on every step of the toy baseline. And
`tools/diff_engine.py` generates random scenarios, runs both, and compares their output
byte for byte, including the scenarios that fail.

When the two disagree, the oracle is right unless this document says otherwise, and the
fix goes into the engine. When the contract itself changes, the oracle changes first.
