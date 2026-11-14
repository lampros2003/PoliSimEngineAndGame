# Model-file format 0

A model is a folder of TOML files plus CSV data. The engine contains no model: everything
it simulates is read from these files, and the base game will be one such folder. The
loader that defines this format is `oracle/polisim_oracle/model.py`; a complete example
is `models/toy/`.

Related: [engine contract](00-engine-contract.md), [formula language](02-formula-language-v0.md).

## Files

`model.toml` is the manifest. It may list further TOML files in `model.files`; all files
are merged, and declaring the same name twice is an error. Paths are relative to the
folder holding `model.toml`.

The **model hash** is SHA-256 over every TOML file and every data file, each preceded by
its relative path. Files are hashed byte for byte, so the repository forces LF line
endings (`.gitattributes`).

## Names

Every declared thing has a name matching `[A-Za-z_][A-Za-z0-9_]*`. All names in a model
share one namespace, and function names and the words `and or not true false` are
reserved. The full identifier of an element is `<model id>:<section>.<name>`, for example
`toy:flow.income_tax`; formulas use the bare name.

## Types and units

`type` is one of:

| `type` | Stored as | Written in files as |
|---|---|---|
| `money` | whole number of minor units | a number in **major** units: `800`, `12570.50` |
| `int` | whole number | a whole number |
| `real` | real | any number |
| `bool` | true/false | `true` / `false` (in CSV: `1`/`0` or `true`/`false`) |

A `money` value times `minor_units` must be a whole number, otherwise the file has more
decimal places than the currency and loading fails. A value with a fractional part is read
as the shortest decimal that gives the same 64-bit float (Python's `repr`), which is what
was typed, and scaled exactly: `2301745961.03` pounds is 230174596103 pence, although the
floating-point product is 230174596102.99997. In formulas `money` and
`int` are the same kind of value.

Money is held in minor units everywhere at run time. A `real` whose unit includes the
currency (an average wage, say) is therefore also in minor units, and its value in a file
must be written in minor units: the loader scales only `money`. The unit checker cannot
catch a real written in major units, because pounds and pence share one unit name.

`unit` is a product of named base units with integer powers, read left to right:
`"GBP/month"`, `"GBP/month/household"`, `"1/month"`, `"share"`, `"1"`. Base units are
whatever names the model uses; there is no built-in list. A quantity held per record of an
entity carries that entity in its unit (`GBP/month/household`), which is how the checker
catches a national total used where a per-household amount belongs.

## Sections

### `[model]`

| Key | Meaning |
|---|---|
| `id` | the model's namespace |
| `format` | must be `0` |
| `currency`, `minor_units` | currency code and minor units per major unit (`100`) |
| `step` | the unit of one step, such as `"month"` |
| `phases` | ordered list of phase names |
| `files` | further TOML files to merge (optional) |

### `[sector.<name>]`

A balance-sheet holder. `entity = "<entity>"` makes its accounts record-level: one
balance per record of that entity. Without it the sector has one balance per instrument.

### `[instrument.<name>]`

A financial claim. `unit` is its unit; `issuer` is the sector whose balance is the
negative of all other holdings. The issuer may not be a record-level sector.

### `[account.<name>]`

One sector's balance in one instrument: `sector`, `instrument`, optional `range`.
Holders give `initial`; the issuer's account must not, because it is derived. `initial`
is a number, or `{ column = "<csv column>" }` for a record-level account. The account's
unit is the instrument's, divided by the entity for a record-level account.

### `[entity.<name>]`

A table of records: `data` (CSV path), `id` (column of unique non-negative whole
numbers), `weight` (column of positive whole numbers: how many real units each record
stands for). `[entity.<name>.columns.<column>]` declares a data column that formulas may
read, with `type` and `unit`. Other CSV columns can be used only as `initial` values.

### `[param.<name>]`

A constant of a run: `type`, `unit`, optional `range`, and either `value` or the three
presets `low`, `central`, `high`. A scenario picks a preset and may override any
parameter.

### `[lever.<name>]`

A value the player sets: `type`, `unit`, `default`, optional `range`. Changed only by
commands, which take effect before the phases of the step they name. Optional
`player = false` marks an input that scenarios set but the game does not offer the
player, such as world demand or a market interest rate in a historical run; it behaves
like any other lever.

### `[table.<name>]`

`kind = "marginal"` is the only kind in format 0. `unit` is the unit of the thresholds.
`bands` is a list of `{ from = "<formula>", rate = "<formula>" }` in ascending order of
`from`; both are national formulas, so they can name parameters and levers. Used by
`marginal()`.

### `[stream.<name>]`

Declares a random stream for `rand()`. Its id is the FNV-1a hash of its name; two streams
whose ids collide are a load-time error.

### `[var.<name>]`

A value recomputed every step: `type`, `unit`, `phase`, `expr`, optional `entity` (one
value per record), `range`, and `initial` (required if any formula reads it through
`prev()`).

### `[state.<name>]`

A value that persists: `type`, `unit`, `phase`, `initial`, `next` (the formula for its
new value), optional `entity` and `range`. See the engine contract for when the new value
becomes visible.

### `[flow.<name>]`

A payment: `from` and `to` (two different sectors), `phase`, `expr` for the amount,
optional `instrument` (default: the first declared). It is record-level when either
sector is; a flow between two record-level sectors is not in format 0. Its type is
`money` and its unit is derived: the instrument's unit per step, per record if
record-level. A flow's amount can be read by name like a `var`. Optional
`financial = true` marks a purchase or sale of an asset (paying for gilts, drawing a
loan) rather than income or spending; it changes nothing in a run, and budget screens
leave such flows out.

Any element may carry `doc`, a sentence for people and for generated documentation.

## Scenario files

A scenario is a TOML file outside the model hash:

```toml
[scenario]
model = ".."            # path to the model folder, relative to this file
seed = 20261113
steps = 240
preset = "central"      # which of low / central / high to use

[params]                # optional overrides
[levers]                # optional starting settings

[[command]]             # zero or more
step = 120
set = { gov_purchases = 1_600_000_000 }
```

## Load-time checks

Loading fails, naming the element and showing the formula, when: a name is reused or
reserved; a type, unit, phase, sector, instrument or entity is missing or unknown; a
formula has a syntax, type or unit error; a formula reads something computed in a later
phase; formulas within a phase depend on each other in a circle; something read through
`prev()` has no `initial`; or a value does not fit its declared type.

## Planned, not in format 0

Patches (`[[patch]]` entries that edit one named element of another model), multiple
namespaces, further table kinds, and native operators. Dimensions such as age, region and
industry, with sums over them and cohort ageing, are [format 1](06-model-format-1.md).
