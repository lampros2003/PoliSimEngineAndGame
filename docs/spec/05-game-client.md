# The game client (stage S2)

How the Godot client, the engine and the model files fit together. The client is written
for no particular model: everything on screen comes from the model's catalogue and the
scenario's `[play]` table.

Related: [engine contract](00-engine-contract.md), [model format](01-model-format-v0.md),
[save format](04-save-format-v0.md).

## Pieces

| Path | Language | Role |
|---|---|---|
| `crates/core/src/describe.rs` | Rust | The catalogue: every named value with kind, unit, label, help text and result-row name, and the flows into and out of each sector |
| `crates/core/src/explain.rs` | Rust | Why a value changed over the last step |
| `crates/core/src/session.rs` | Rust | A game: run, history, policy changes, pending changes, saved games |
| `crates/godot/` | Rust | The `PoliSim` class Godot sees; runs the session on its own thread |
| `client/` | GDScript | The screen: `scripts/main.gd` and one script per panel |

## The scenario's `[play]` table

Presentation settings. The engine ignores them and they never affect a run.

| Key | Meaning | Default |
|---|---|---|
| `country` | Name shown in the title bar | the scenario's file name |
| `currency_symbol` | Shown before money, with a space only if it ends in a letter (`£12.4bn`, `Cr 12.4bn`) | the model's currency code |
| `amounts` | `"year"` to show flows (values whose unit is per step, such as `GBP/month`) at an annual rate, twelve times the month, as published accounts are; `"step"` to show them per step. The player can switch with the "Amounts a year" button; lever inputs follow the same choice | `"step"` |
| `start` | The month step 0 covers, as `YYYY-MM` | `2027-01` |
| `term` | Steps in a term; the end-of-term summary appears after this many | 60 |
| `government` | The sector whose flows make up the budget screen | `government` |
| `headline` | Up to six result-row names for the headline strip; a leading `-` shows the value negated (an account held as a negative number, such as public debt) | `watch` |
| `watch` | Values `polisim play` prints after each step | none |
| `labels` | Overrides of labels by key, including negated keys such as `"-gov_money"` | none |
| `breakdowns` | Names of values with one dimension for the "Who gains, who loses" panel, in the order of its menu (format 1; see below) | none: no panel |
| `breakdown_all` | The national value the breakdowns average to, shown as their last line, "All households" | none |

Any model element may carry `label` (a short name) and `doc` (a sentence) for the
client's labels and tooltips. A `real` whose unit starts with the currency (an average
income, `GBP/month/household`) is shown as money: it is held in minor units like money
itself ([model format](01-model-format-v0.md)).

## Who gains, who loses

A panel under the budget shows each breakdown named in `[play] breakdowns`: one line per
member of the value's dimension, labelled with the dimension's `labels`, giving this
month's value and its change on last month in money, in percent and as a bar (green for a
rise, red for a fall; the longest bar is the largest change, or 0.5% if every change is
smaller). A menu picks the breakdown. The value's label names the panel's note, up to its
last comma ("Net income per household, by income decile" gives "Net income per household"
and the menu item "By income decile"). Amounts follow the "Amounts a year" choice.

The UK scenario shows net income per household (pay and pensions after income tax and
National Insurance, with Child Benefit and Universal Credit) by income decile, household
type and region, from the synthetic households (`models/uk/households/README.md`).

## Explaining a change

For the last completed step `t`, and a value `x` computed by a formula `f`:

- The **change** is `x` at the end of step `t` minus `x` at the end of step `t - 1`.
- The **context** of step `t` is what `f` read while step `t` ran: the end-of-step values
  of levers, variables and flows, the start-of-step values of accounts and of states not
  yet updated in the formula's phase, and the end of step `t - 1` for anything read through
  `prev()`. It is rebuilt from end-of-step snapshots; the explanation checks that `f` in
  this context reproduces `x` exactly and refuses to explain otherwise.
- The **effect** of one input is `f(context of t)` minus `f(context of t with that one
  input taken from the context of t - 1)`. Random draws count as an input: their effect
  uses step `t - 1`'s draws.
- The **remainder** is the change minus the sum of effects. It is zero for any formula
  that adds and subtracts its inputs; otherwise it is the part due to inputs acting
  together, and the client shows it.
- An **account**'s change is split into the flows that entered and left it during step
  `t`, which is exact.
- A per-record value is explained through its weighted total over all records.

Explanations need snapshots of the last three end-of-step states, so they are available
from the second completed step after a game starts, loads or reloads.

## Reloading a model

The model files are read again and the run continues on the new model from the same
step. Lever settings, account balances, states and remembered values are carried across
when the new model has a value of the same name, kind, type and shape; anything else
starts from the new model's initial value and is listed for the player. Parameters and
formulas come from the new files. If the new files fail to load, nothing changes and the
error is shown. Reloading unchanged files gives exactly the run that was never reloaded
(tested).

## Saved games

A saved game is the engine save (save format 0) plus the commands still to come, the
policy changes made (with their votes, from version 2), the full history of every result and the last two steps' values,
dimensioned values' cells included, in one file (`crates/core/src/session.rs` documents the
layout). Version 1 added the cells; a version 0 file still loads, and its panels by
dimension fill from the next month. Loading continues exactly
and brings the charts back. A saved game belongs to the model files it was made with.

## The bridge

GDScript creates `PoliSim.new()` and calls `open(scenario_path)`. Requests (`advance`,
`set_lever`, `cancel_lever`, `request_explanation`, `save_game`, `load_game`,
`reload_model`) go to a worker thread in order; `poll()` returns what has finished, as
dictionaries with a `kind` key. Everything the screen reads (`latest`, `previous`,
`pending`, `series`, `changes`, `hashes`, `catalogue`, `play_settings`, `cells`) comes
from a mirror the worker refreshes after each request, so reading never waits for the
simulation. No Godot object is touched off the main thread.

Stage S5.4: the catalogue says whether the model has a `legislature`, and each lever's
`leaning`; `changes()` gives each policy change's vote (`passed`, `votes_for`, `seats`).
The policy panel then says that changes are bills; a defeated bill is announced after
the step and never marked on the chart.

Format 1: the catalogue gives each entry's `dims` (dimension names) and a `dims` list of
every dimension with its members' `labels`. `cells(name)` returns a value with one
dimension: `values` and `previous` (the cells after the last step and the one before, in
member order; `previous` is empty after the first step), `dim` and `labels`. Only values
of one dimension of at most 64 members are mirrored, so the mirror stays small; others
return an empty dictionary.

Values come back as the engine stores them (money in minor units). Lever settings go in
as a person types them (money in major units, rates as fractions), and are checked
against the lever's range before they are accepted.

## How the client is tested

`tools/check_client.py` runs six scripted sessions in Godot without a display and
compares them with the command-line runner or with published figures:

| Script | Checks |
|---|---|
| `tests/scripted_run.gd` | 60 months through the bridge with lever changes: the same state hash as the runner on every step |
| `tests/ui_run.gd` | The same through the interface's controls (typed values, button presses), with a save, an unchanged reload and a load along the way |
| `tests/reload_run.gd` | A typo in a model file is reported and the game carries on; a real change takes effect the next month |
| `tests/second_model.gd` | A model with different names (`models/mini`) gets a working budget, levers and headline |
| `tests/bill_vote.gd` | Stage S5.4: in the UK's early-election test scenario, the coalition's basic rate cut is voted down 283 to 367: the rate keeps its value, the change is recorded as defeated, the player is told, and the chart marks nothing |
| `tests/budget_dump.gd` | The UK's budget screen after one month, read as text and parsed back: every line within 1% of the 2024 public finances in `models/uk/data/annual.csv` (totals, shown to three figures, within 0.6%); and no input marked `player = false` in the policy panel. Then the "Who gains, who loses" panel, every breakdown, after that month and after a second with the basic rate one point higher: every group shown with its label; all households' net income equal to the runner's to the pound; the rise taking from the fifth decile up, from each of the top three at least £100 a year more than from the poorest, and from every region but Scotland, which sets its own rates |

`tests/screens.gd` saves screenshots of a scripted toy session, and `tests/look.gd` one
screenshot of any scenario (`--scenario`, `--months`, `--chart=a,b`, `--why=name`,
`--shot=FILE`), for a person to look at; on a server they need `xvfb-run`. Godot's
`--resolution 1440x2100` before `--path` gives a tall window that shows the whole left
column.

## Lever inputs

A lever's optional `group` (a name) places it under that heading in the policy panel, in
the order the groups first appear; groups other than Spending, Taxes and Income tax start
folded, with the number of levers they hold.

Rates are typed in percent. Money is typed in major units, or in millions (`m`) or
billions (`bn`) when the top of the lever's range is at least ten million or ten billion
in the units shown; a lever whose unit is per step follows the "Amounts a year" choice,
so a monthly bill is typed as a yearly figure and divided by twelve, to the penny, when
it is sent to the engine.
