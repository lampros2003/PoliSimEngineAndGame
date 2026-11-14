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
| `breakdown_totals` | A table from breakdown names to the national value shown as their last line instead, under its own label (stage S6.4: jobs by industry and their total) | none |
| `politics` | A table naming the model's politics for the politics panel and election night (stage S5.5): `intention`, `seats`, `projected` (values over one dimension of blocs: voting intention, seats held, seats if an election were held now), `governing` (true/false by bloc), `support` and `turnout` (national: the government's poll rating, turnout), `election` (true in a month with a general election), `months_to_election`, `player` (true while the player's bloc governs) and `majority` (seats) | none: no panel |

Any model element may carry `label` (a short name) and `doc` (a sentence) for the
client's labels and tooltips. A `real` whose unit starts with the currency (an average
income, `GBP/month/household`) is shown as money: it is held in minor units like money
itself ([model format](01-model-format-v0.md)).

## Connections: the icon web

Stage S6.1. The catalogue gives each entry its `inputs` (the names its formula reads this
step) and `lagged_inputs` (through `prev()`); an account's inputs are the flows into and
out of it. The lower right has two tabs, "Why did it change?" and "Connections": the web
puts a value in the middle, what it depends on to the left and what depends on it to the
right, each as a tile with its value and last month's change (bordered green for a rise,
red for a fall), the ten that moved most on each side and a count of the rest. Data
columns and parameters are left out: they never change. Pressing a tile moves the web to
it; Back returns. Pressing Why anywhere moves the web as well as the explanation.

## Politics

With a `[play] politics` table, a panel under "Who gains, who loses" shows the House of
Commons as a bar of seats by bloc (the governing blocs first, a line at the majority),
then for each bloc its voting intention and the change on last month, its seats, and its
seats if an election were held now (blocs under half a percent with no seats are
hidden), with the government, its seats, its poll rating and turnout above, and the next
general election's month. In a month with an election, a dialog gives the results (votes,
seats, change) and the new government. When the player's bloc is out of government the
game is over: time stops, and a saved game can still be loaded.

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
type and region, from the synthetic households (`models/uk/households/README.md`); and
jobs and pay per employee job by industry (stage S6.4), each with its national total as
the last line (`breakdown_totals`). A breakdown with a total of its own takes its note
from the value's `doc` (or its label when it has none), and only money is said to be "at
an annual rate". Two breakdowns whose labels end the same ("..., by industry") keep their
full labels in the menu. Numbers of people (unit `person`) are shown whole, to the
person, below 100 million, and their changes too.

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

A saved game is the engine save (save format 1) plus the commands still to come, the
policy changes made (with their votes, from version 2), the full history of every result and the last two steps' values,
dimensioned values' cells included, in one file (`crates/core/src/session.rs` documents the
layout). Version 1 added the cells; a version 0 file still loads, and its panels by
dimension fill from the next month. Loading continues exactly
and brings the charts back.

Stage S7.0: a game saved with other model files (an older version of the model, or one the
player has edited) still loads. The game carries on with the current model, carrying every
value that still fits ([save format 1](04-save-format-v0.md#loading-into-a-changed-model));
scheduled changes to levers the model no longer has are dropped, the record of policy
changes and the charts' history are kept, and the player is told how many values were
carried, which started again, which policies were moved to their new limits, and what
was renamed or is gone. A game saved before format 1 loads only with its own model files.

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

`tools/check_client.py` runs eleven scripted sessions in Godot without a display and
compares them with the command-line runner or with published figures:

| Script | Checks |
|---|---|
| `tests/scripted_run.gd` | 60 months through the bridge with lever changes: the same state hash as the runner on every step |
| `tests/ui_run.gd` | The same through the interface's controls (typed values, button presses), with a save, an unchanged reload and a load along the way |
| `tests/reload_run.gd` | A typo in a model file is reported and the game carries on; a real change takes effect the next month |
| `tests/migrate_check.gd` | Stage S7.0, run twice on a copy of Valmora: a game saved after four months with the basic rate at 30%; then, with the model's files changed (a new state, the basic rate limited to 25%), the save loads, the rate is at 25%, the player is told, and the next month runs on the new model |
| `tests/second_model.gd` | A model with different names (`models/mini`) gets a working budget, levers and headline |
| `tests/politics_check.gd` | Stage S5.5, run twice: in `2025.toml`, after a month the panel shows the 2024 House (411 centre-left seats and the rest), the government's poll rating and the next election in July 2029; in `early_election.toml`, the election in the second month is announced, the player has lost office, and advancing no longer moves time |
| `tests/web_walk.gd` | Stage S6.1: in `2025.toml`, the icon web walked by pressing tiles from the basic rate to the government's poll rating along the model's own chain (eleven steps, through each household's income tax and income change and the voter types' choice), and Back |
| `tests/bill_vote.gd` | Stage S5.4: in the UK's hung-parliament test scenario the player's coalition raises the basic rate and is voted down 323 to 327: the rate keeps its value, the change is recorded as defeated, the player is told, and the chart marks nothing |
| `tests/budget_dump.gd` | The UK's budget screen after one month, read as text and parsed back: every line within 1% of the 2024 public finances in `models/uk/data/annual.csv` (totals, shown to three figures, within 0.6%); and no input marked `player = false` in the policy panel. Then the "Who gains, who loses" panel, every breakdown, after that month and after a second with the basic rate one point higher: every group shown with its label; all households' net income equal to the runner's to the pound; the rise taking from the fifth decile up, from each of the top three at least £100 a year more than from the poorest, and from every region but Scotland, which sets its own rates |

`tests/screens.gd` saves screenshots of a scripted Valmora session (`--scenario=models/valmora/scenarios/term.toml`), and `tests/look.gd` one
screenshot of any scenario (`--scenario`, `--months`, `--chart=a,b`, `--why=name`,
`--tab=N`, `--breakdown=name`, `--shot=FILE`), for a person to look at; on a server they need `xvfb-run`. Godot's
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
