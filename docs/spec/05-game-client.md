# The game client (stages S2 to S13)

How the Godot client, the engine and the model files fit together. The client is written
for no particular model: everything on screen comes from the model's catalogue and the
scenario's `[play]` table, and, for the board, its `[play.web]` table.

Related: [engine contract](00-engine-contract.md), [model format](01-model-format-v0.md),
[save format](04-save-format-v0.md).

## Pieces

| Path | Language | Role |
|---|---|---|
| `crates/core/src/describe.rs` | Rust | The catalogue: every named value with kind, unit, label, help text and result-row name, and the flows into and out of each sector |
| `crates/core/src/explain.rs` | Rust | Why a value changed over the last step |
| `crates/core/src/session.rs` | Rust | A game: run, history, policy changes, pending changes, saved games, forks for looking ahead |
| `crates/godot/` | Rust | The `PoliSim` class Godot sees; runs the session on its own thread |
| `client/scripts/main.gd` | GDScript | The screen: the top bar, the board, popups, sheets, the month's report, keys, settings, and the methods the scripted checks call |
| `client/scripts/web.gd` | GDScript | The board: layout, nodes, links, gauges, flags, the automatic board |
| `client/scripts/popup.gd` | GDScript | The one popup, which grows from a node and has Back |
| `client/scripts/lever_panel.gd` | GDScript | A policy's popup: controls, cost, vote, "In a year", history |
| `client/scripts/introduce_list.gd` | GDScript | An area's list of policies not in force |
| `client/scripts/indicator_card.gd` | GDScript | An indicator's popup (also a budget line's, a top-bar figure's, a situation's) |
| `client/scripts/group_card.gd` | GDScript | A group's popup and a household's account |
| `client/scripts/sheet.gd` | GDScript | A sheet laid over the board: the Budget, Parliament, a question, election night, help |
| `client/scripts/budget_panel.gd`, `politics_panel.gd` | GDScript | The contents of the Budget and Parliament sheets |
| `client/scripts/month_report.gd` | GDScript | The month's report |
| `client/scripts/guide.gd` | GDScript | The first-minutes guide |
| `client/scripts/start_screen.gd` | GDScript | The start screen |
| `client/scripts/trace_panel.gd`, `breakdown_panel.gd`, `chart.gd`, `bar.gd` | GDScript | "Why it moved last month", the breakdown tables, the history chart, a signed bar |
| `client/scripts/format.gd`, `palette.gd`, `sound.gd` | GDScript | Numbers, dates and units for people; the look (colours, type, pictograms, theme); the interface's sounds |
| `client/icons/`, `client/fonts/`, `client/sounds/` | Assets | Pictograms from game-icons.net (CC BY 3.0), Jost and IBM Plex Sans (OFL), Kenney's Interface Sounds (CC0); each folder holds its credits or licences |

## Starting a game

Stage S7.1. Started with `--scenario=PATH` (after `--` on Godot's command line, as the
tests and the Valmora launcher do), the client opens that scenario, with the mods in
`--mods=a,b` (folders) after the scenario's own, and in `--language=CODE` if given. It
stays at step 0, and every figure reads as awaiting the first month. Without it, it shows
the start screen (`client/scripts/start_screen.gd`): every scenario with a `[play] title`
under the game's `models` folder, the one picked described by its `summary`; the mods for
its model (a mod that names another model is not offered), from the game's `mods` folder and
the player's own (`user://mods`, created if missing and named on the screen), each with a
tick box and its description; a mod that cannot be read is shown with its error; and,
when the model has text in other languages ([text](08-text.md), stage S7.4), a choice of
language, the model's own words first. **New game** starts the scenario with the ticked
mods and plays its first month, so that no figure is blank (stage S13.6); **Continue saved
game**, when the scenario has a save, opens it and loads the save, mods and all. The title
bar names the mods in play, and notes from loading them ([mods](07-mods.md)) are shown when
the game starts.

A game started from the start screen, with a display, whose player has not seen the guide
(`guide/seen` in `user://settings.cfg`) opens the guide (`guide.gd`) once its first month is
in: up to five steps, each a card with an arrow to something on the board (the centre; the
first policy, indicator and group of the largest size; and **Next month**), a step whose
target the model lacks being left out. Esc or Skip ends it, and the menu's "Show the guide
again" repeats it. It is never shown for a `--scenario` game or without a display.

## The screen

The window holds the top bar and the board, and over them at most one popup and one sheet,
the month's report and the guide. Nothing else.

**The top bar.** From left to right: the country (with the mods in play) and the month; a
button for each of the first six values of `[play] headline` (or of `watch` when there is
no `headline`), showing the value and its change on last month, which opens that value's
popup; the political capital, when the model has it and the bar is at least 1,560 pixels
wide (it opens Parliament; on a narrower bar the capital shows at the centre only); a
status line; **Next month**, **3 months** and **Year**; **Budget** and **Parliament**,
which keep only their pictograms on a narrow bar; and **Menu**. Pressing the month shows
the month's report again. A `headline` name with a leading `-` is shown negated. A figure's
label is `[play] labels[key]`, else the catalogue's.

**The menu.** Save, Load, Reload model; "Amounts a year" (a check item: flows at an annual
rate or per step); "See the whole board"; "Size of the screen" (Automatic, 100%, 125%, 150%,
175%, 200%); Sound (a check item) and Volume (25%, 50%, 75%, 100%); "Show the guide again";
Help. The screen size is `ui/scale` in `user://settings.cfg` (0 for automatic: the window's
height over 960 pixels, rounded to a quarter and held between 1 and 2, applied as the
window's content scale); sound and volume are kept there too. Help is a sheet with the
essentials and the credits for icons, type and sounds.

**Keys.** Handled by `main.gd` unless a text field has the focus or the guide is open:
Space, Enter or Keypad Enter, next month (not while a question waits); B and P, open or
close the Budget and Parliament; H or Home, close the popup and fit the board; Esc, close
the popup, else the topmost closable sheet. Handled by the board while no popup or sheet
covers it: the arrow keys move the board, `+` and `-` zoom, Home fits it.

**The month buttons** are off while the game is busy and after the player has lost; while a
dilemma waits, pressing one asks the dilemma. Advancing closes the popup and the report,
and records what the report will compare with.

## The board

Stage S13.2. `web.gd` is one `Control` filling the window below the top bar, drawn in
three layers (the rings and area names; the links; the nodes and their effects) so that
pointing redraws only what moved. The layout is authored and stable: nodes are placed by
rule from the scenario's `[play.web]`, never by simulation, and pan and zoom move the view,
not the layout. Zoom runs from 0.6 to 3 times; dragging pans (a press that moves under five
pixels is a click); the wheel zooms about the pointer.

**Rings.** Concentric ellipses, wider than tall, fitted to the window.

| Place | Nodes |
|---|---|
| Outer ring | Policies, in an arc for each area, in the order `[[play.web.areas]]` lists them, with the area's name set along the rim outside. An area's share of the ring is what its policies need, or what its indicators need on the middle ring over the same angle, whichever is more |
| Middle ring | The indicators of each area, in that area's sector; a sector too narrow for them in one row puts every second one in a second row on an inner ring, between the first row's nodes |
| Group band | Interest groups, on a ring round the centre, a small gap between families |
| Centre | One medallion |

A board with more nodes than its rings hold draws them smaller, to two thirds of their
size at least, and never overlapping. Labels are placed at rest where they fit and clear of
other nodes, labels and flags; the largest nodes have the larger type.

**Node kinds.**

| Kind | Shape | Size | Gauge and marks |
|---|---|---|---|
| `policy` | Disc with a pictogram | Three tiers, from `size`: radius 17, 22 or 29 pixels | A gauge arc over three quarters of a circle from the lower left: where the first lever's value sits between its minimum and maximum (when the maximum is more than four times the starting value, and the minimum is nought, the top is twice the starting value). A short ochre line on the gauge marks the change waiting, and an ochre dot on the node says one is waiting on any of its levers. A policy to be introduced, its bill waiting, is a ghost: dashed edge, faint pictogram, no gauge |
| `indicator` | Ring with a pictogram | The same three tiers | A triangle for last month's rise or fall, sage or brick where `better` says which is good and ink where it does not; a pulse after a month in which it moved by at least 0.1 points (a rate) or 0.5% |
| `group` | Shield with a pictogram | From the group's share of the electorate: radius 14 to 25 pixels, growing as the square root of the share over 0.8, in whole pixels | A gauge of its approval, and the same triangle. A group with a `note` and an approval of nought shows a dash |
| `introduce` | Dashed disc with a plus | One tier | The number of policies to choose from, on a small badge |
| `centre` | Large medallion | | The government's approval, its change, the months to the election, and the political capital with what bills waiting would spend |
| `flag` | A tab | | A situation in force, a question waiting ("Decide: ..."), or an answer while it lasts |

The centre's approval is `[play.politics] support` (else the first headline value). Flags
stand in the window's corners (top left, top right, bottom left, bottom right in turn) when
the board has groups, and in columns beside the centre when it has none. A situation's flag
says "since <month>" and is tinted by its tone; it opens the situation's popup. A question's
flag asks it.

**Links.** Only the node under the pointer (else the selected node) has links drawn; the
rest of the board dims, and the links draw in over about 0.15 s. A link has a direction
(an arrow from cause to effect), a sign (blue for a rise, brick for a fall) and a strength
(the line's width and the flow of its dashes).

- A policy's links go to indicators and groups. For the policy's first lever, the client
  takes each row's change from the effects table (below), divides it by that row's scale,
  the median change in that row over every lever of the table above a floor of 0.0005, so
  that a rate and an amount of money compare, caps the ratio at ten, and multiplies it by
  the square of the target's tier. The seven best indicators and three best groups are
  drawn, and the budget balance (`[play.web] balance`) as well whenever the policy moves it.
  A policy of several levers is measured by its first, so a link's sign always means
  "raising this". Until the table has arrived, or for a target it does not cover, the links
  go to the nodes the policy's levers reach through the model's formulas without passing
  another node on the board (a search over each catalogue entry's `inputs` and
  `lagged_inputs`), drawn in neutral colour at one strength. A ghost has no links.
- An indicator's or a group's links come from the policies that move it most, the same
  table read the other way, seven at most.
- While the table arrives for a node held under the pointer, its links change at most once,
  from the formulas' to the measured; measured links already shown stay until the pointer
  moves on.

**The effects table.** After a game opens and after each month, once the screen has been
idle for 1.5 s, the client calls `request_effects(levers, 12)` for every lever of a board
policy ([Looking ahead](#looking-ahead-stage-s131)). For each lever it keeps, for each row,
the change as a share of the as-is value (ten times the change in the rate, for a rate),
signed as for a rise when the table had to nudge the lever down. A month discards it.

**Pointing and selecting.** Pointing sets the hover, which the links follow; a click on a
node opens its popup and selects the node while the popup is open. The pointer leaving the
board, or a popup or sheet opening over it, clears the hover.

**What a node says.** After each month the client sets every node's value, change and trend
and pulses those that moved notably. A policy's value is its lever's value as the policy's
`levels`, `unit` and `per` read it; one whose repeal waits says so.

**The automatic board.** A scenario with no `[play.web]` gets a board made from the model:
one area for each lever `group`, in the order the model names them (levers with none go to
"Policy"); one policy for each lever, of the largest tier when the model has twelve levers
or fewer and the middle one otherwise, with a generic pictogram; the `headline` and `watch`
rows as indicators (the largest tier for a headline row, the middle one for the rest), each
in the sector of the first area whose levers reach it through the formulas, or of the area
with fewest indicators; no groups, so the middle is empty. Nothing is hidden and nothing can
be introduced.

## Popups

`popup.gd` shows one popup at a time: a card that grows from the node, top-bar figure or
budget line that was clicked, closes faster than it opens, and dims the board, which then
ignores the pointer. Esc or a click outside closes it. Following something inside it (a
cause, a policy, a group) replaces its content and offers **Back**. `main.popup_kind()`
names the kind open: `policy`, `indicator`, `group`, `household` or `introduce`.

**Policy** (`lever_panel.gd`). The area, the policy's name, and its lever's `doc` when it has
one lever. One control for each lever, with its setting now and any change waiting (ochre,
with **Undo**):

- A number is a slider with an exact field. Rates are typed in percent; money in major
  units, or in millions (`m`) or billions (`bn`) when the top of the range is at least ten
  million or ten billion in the units shown; a lever whose unit is per step follows the
  "Amounts a year" choice, so a monthly amount is typed as a yearly figure and divided by
  twelve, to the penny, when it is sent to the engine. An age or a year is whole; with a
  `unit` of `multiple` the field reads as a change on 2024's rates; with `per`, the amount
  is followed by it.
- A policy with `levels` is a row of named steps, from the lever's minimum.

A change is a bill: the bridge's `set_lever` takes it and `bill_cost` prices it. The popup
shows the cost in political capital of the bills waiting against the capital there is (and
says when not all can be put to the Commons), and, from `vote_preview`, the vote each
would get ("The Commons would pass this ..." or "would vote this down", with the count),
with a note when the capital left after the bills before it does not cover its cost.
Without a legislature the popup says that changes take effect from next month.

*In a year.* Beside the controls when the window is at least 1,360 pixels wide, else under
them (the controls then scroll on their own when there are many). With a change waiting in
the policy's levers, 0.3 s after the last edit the client calls `request_forecast` over 12
months with the policy's levers at their present settings. "As is" is then the game with
all the changes waiting, and "changed" the game with this policy's change taken out, so
the table reads as what the change adds. While it runs the heading says so; afterwards it
names the setting ("at £2,500 a car", "repealed"). The rows are the budget balance first;
then up to three lines of the Budget and up to six indicators on the board, taken in the
order of how far each moves for its size (a rate against at least two points, else a share
of its value) weighted by the square of its tier; then, under "The groups it moves most",
the five groups whose approval moves most, in points. A bar is sage where the board's
`better` calls the change good and brick where bad, ink where it says nothing. Each name
opens that indicator's or group's popup. The policy's history chart, with the player's
changes marked, follows the controls; a policy not in force and one with `levels` show none.

*Introducing and repealing* (stage S13.5). A policy is in force when its first lever is not
at its `off` setting. A policy with an `off` and one lever, not in force, is available: off
the board, and listed by its area's `introduce` node (label "New policy"), whose popup
(`introduce_list.gd`) gives each with its pictogram, its `line` (else the first sentence
of the lever's `doc`) and "from N political capital", the cost of the smallest step in (the
next level, else a tenth of the range, towards the other end when that would pass the top).
Choosing one opens its popup, with Back to the list, "not in force" and the control at its
`off` setting; **In a year** and the vote follow the setting picked, and nothing is sent
until **Put to the Commons** ("Bring it in" without a legislature). The bill stands as a
ghost until the vote; when the lever leaves its `off` setting the ghost grows onto the
board, and the area's `introduce` node loses a count (and goes at none). A policy in force
with an `off` has **Repeal**, which sends the `off` setting as a bill and shows its cost and
vote; when it passes, the policy leaves the board and is available again. An `off` on a
policy of several levers is ignored.

**Indicator** (`indicator_card.gd`). The figure and last month's change ("awaiting the
first month's figures" before a month has run); its history, with the player's changes
marked and a menu to lay over it one other board indicator with the same unit; **Why it
moved last month** (`trace_panel.gd`; [Explaining a change](#explaining-a-change)), whose
inputs open their own popups; **Who gains, who loses**, when the value has breakdowns
(`breakdown_panel.gd`): those of `[play] breakdowns` whose total, in `breakdown_totals`, it
is, or, for `breakdown_all`, every breakdown with no total of its own; and **What moves it
most**, the policies that move it, strongest first, from the effects table (else from the
formulas), each opening its popup. A value that is not on the board (a Budget line, a
top-bar figure, a cause followed) gets the same popup without its area.

**Group** (`group_card.gd`). The approval row's figure and change (a dash for a group whose
`note` applies, with the note); its history against the national rating; its share of the
electorate as a hundred figures; **What is moving them**, each driver of `group_drivers` as a
signed bar, read from `cells()` at the group's place in the group dimension (the member
whose `group_share` is nearest the group's share); **Policies that matter most to them**,
from the effects table; and **Households**: the bridge's `request_records(entity, flag, 8,
columns, key)` for the group's `households` flag, with the columns `household` names, shown
as eight pictograms (adults and children), each with a tooltip, which open **a household's
account**: the lines of `household.account` for the year (a leading `-` takes the amount
away) and its net income, "before housing costs; other income is not in the model". A group
with `estimate` has no `households` flag, and says where its membership comes from in their
place.

## Sheets and the month's report

`sheet.gd` is a sheet over the board with a title and a close button, closed by Esc or a
click outside when `closable`. Opening one closes the popup and any other sheet.

- **The Budget** (`budget_panel.gd`): the flows into the sector named by `[play] government`
  (revenue) and out of it (spending), this month and last, with totals, each line opening
  its popup; its title says "at an annual rate" when amounts are shown a year. Its lines
  are the budget lines the year-ahead table may list.
- **Parliament** (`politics_panel.gd`, only with `[play.politics]`): the House as rows of
  seats by bloc, the governing blocs first, a line at `majority`; for each bloc its voting
  intention and change, its seats, and its seats if an election were held now (blocs under
  half a percent with no seats are hidden); the government, its seats, rating and turnout;
  the month of the next general election; the issues voters weigh against the last election
  (`issues`, `issues_at_election`); and "The country by group": each group's share,
  approval and change, a row opening the group's popup. In a month with an election a sheet
  gives the results (votes, seats, change) and the new government. When the player's bloc
  is out of government the game is over: time stops, and a saved game can still be loaded.
- A question (a dilemma), election night and Help are sheets too.

**The month's report** (`month_report.gd`). After the months of an advance have run, a card
docks at the right under the top bar, and the board is fitted to the room left of it. It has
up to three sections: *Bills*, each change put to the Commons since the advance began, in
words such as "Fuel duty to 62.95p a litre", "Electric car grant introduced at £2,500 a car"
or "Electric car grant repealed", marked passed, voted down (with the count) or refused
(with the capital it needed); *Moved most*, up to four board indicators and groups, ranked
by the change against the value's own mean monthly move over the two years before, tinted
by `better`; and *Situations* that began or ended. A line opens its node's popup. The card
goes after nine seconds, but not while the pointer is on it, or on a click. Nothing is
shown after the base month when no bill was put.

## Situations

Stage S7.3. The model's situations ([model format 1](06-model-format-1.md#situations-stage-s73))
that are on are shown as flags on the board, each with the month it began (from the
history) and its `doc` as a tooltip, tinted red, or green for a good one; a flag opens the
situation's popup. After each
step the player is told which situations began, with their `doc`, and which are over,
added to any other message of that step. Nothing is announced for a game just opened,
loaded or reloaded.

## Dilemmas

Stage S9.1. The catalogue lists the model's dilemmas ([model format
1](06-model-format-1.md#dilemmas-stage-s91)) with their answers, in the model's words or
the game's language. When a step leaves a dilemma open with no answer given for the next
month, the client asks it in a dialog: its `doc`, each answer's label and `doc`, and a
button for each answer. Choosing one sets the dilemma's lever to the answer's number, for
the next month. No month runs while a dilemma waits: the month buttons are off, and a run
of several months (a quarter, a year) stops at the month the dilemma opens, which the
bridge enforces on its own thread (`Session::unanswered_dilemmas`). The player may close
the dialog to look around; the flag "Decide: <label>" asks again.
Once answered, a flag shows the answer, "from next month" until it applies, then
"until <month>" for an answer that lasts some months, or the answer alone for one that lasts
for good. A dilemma's lever is not a policy on the board (its catalogue entry has `player`
false and `dilemma` set). `polisim play` asks a dilemma the same way, as numbered answers
for `set <name> N`.

## The scenario's `[play]` table

Presentation settings. The engine ignores them and they never affect a run.

| Key | Meaning | Default |
|---|---|---|
| `title`, `summary` | Stage S7.1: the scenario's name and a sentence about it on the start screen, which lists only scenarios with a `title` | not listed |
| `country` | Name shown in the title bar and the top bar | the scenario's file name |
| `currency_symbol` | Shown before money, with a space only if it ends in a letter (`£12.4bn`, `Cr 12.4bn`) | the model's currency code |
| `amounts` | `"year"` to show flows (values whose unit is per step, such as `GBP/month`) at an annual rate, twelve times the month, as published accounts are; `"step"` to show them per step. The player can switch with the menu's "Amounts a year"; lever inputs follow the same choice | `"step"` |
| `start` | The month step 0 covers, as `YYYY-MM` | `2027-01` |
| `term` | Steps in a term; the end-of-term summary appears after this many | 60 |
| `government` | The sector whose flows make up the Budget | `government` |
| `headline` | Up to six result-row names for the top bar's figures; a leading `-` shows the value negated (an account held as a negative number, such as public debt) | `watch` |
| `watch` | Values `polisim play` prints after each step; the top bar's figures when there is no `headline`; with an automatic board, indicators beside the headline's | none |
| `labels` | Overrides of labels by key, including negated keys such as `"-gov_money"`, for the top bar and the board | none |
| `breakdowns` | Names of values with one dimension, shown as tables in the popups of the values they break down (format 1; see below) | none |
| `breakdown_all` | The national value that the breakdowns with no total of their own average to; they appear in its popup, with it as their last line, "All households" | none |
| `breakdown_totals` | A table from breakdown names to the national value shown as their last line instead, under its own label (stage S6.4: jobs by industry and their total); the breakdown appears in that value's popup | none |
| `politics` | A table naming the model's politics for Parliament and election night (stage S5.5): `intention`, `seats`, `projected` (values over one dimension of blocs: voting intention, seats held, seats if an election were held now), `governing` (true/false by bloc), `support` and `turnout` (national: the government's poll rating, turnout), `election` (true in a month with a general election), `months_to_election`, `player` (true while the player's bloc governs) and `majority` (seats); and (stage S8.3) `issues` and `issues_at_election` (values over one dimension of issues, 1 where things stood). `support` is also the centre's approval | none: no Parliament sheet |
| `web` | The board: see below | an automatic board |

Any model element may carry `label` (a short name) and `doc` (a sentence) for the
client's labels and tooltips. A `real` whose unit starts with the currency (an average
income, `GBP/month/household`) is shown as money: it is held in minor units like money
itself ([model format](01-model-format-v0.md)).

## The scenario's `[play.web]` table

Stages S13.2 to S13.5. Read by the client only: the engine ignores it, so no model hash
changes with the layout. Names are catalogue names (levers, values) or result-row names as
noted; an item whose name the model lacks is skipped.

| Key | Meaning | Default |
|---|---|---|
| `hide` | Levers the player does not hold on the board (the UK hides Scotland's own income tax rates) | none |
| `balance` | The result row a policy's links always include when it moves it | `budget_balance` |
| `group_share` | The value over the group dimension that gives each group's share, from which a group's place in the dimension is found | `group_share` |
| `groups` | A list of interest groups, each a table (below) | none: no groups |
| `group_drivers` | A table from a driver's key to a value over the group dimension: what moves each group, read with `cells()` | none |
| `group_driver_labels` | A table from a driver's key to its plain name on screen | the value's label |
| `household` | A table naming the households a group's popup shows (below) | none: no households |
| `[[play.web.areas]]` | One table for each policy area, in order round the board (below) | none |

A **group** has `key`, `label`, `icon`, `row` (the national result row of its approval),
`share` (the row of its share of the electorate, which sizes it) and `family` (groups of one
family stand together on the board), and optionally `households` (the per-record true/false
value that picks its households), `note` (said in place of an approval of nought) and
`estimate` (where an estimated group's membership comes from, said in place of households).
A group whose `row` the model lacks is dropped. An `icon`, here and everywhere, is the name
of a file in `client/icons` without `.svg`.

The **household** table: `entity` (the record set, default `household`); `support`,
`net_income`, `change`, `adults` and `children` (values of the entity, by name); `region`
and `type` (each `"column:dimension"`, a data column read as a word through that
dimension's labels); and `account`, a list of the entity's values for the year's account,
a leading `-` taking the amount away.

An **area** has `name` (set along the rim), `icon`, `policies` and `indicators`.

A **policy** has `key`, `label`, `icon`, `size` (1 to 3, the importance, default 2) and
`levers`, one or several, of which the first sets the gauge. A lever the player does not
hold, or that is in `hide`, is dropped, and a policy left with none is dropped. Optional,
stage S13.5:

| Key | Meaning |
|---|---|
| `levels` | The names of a level policy's settings, in order from the lever's minimum; chosen by name, never as a number |
| `off` | The setting, as typed (pounds for money), at which the policy is not in force: off the board, offered by the area's "New policy" node, and repealable when in force. Only for a policy of one lever |
| `line` | One line on what the policy does, in the area's list |
| `unit` | How the value reads: `years` (an age: "18 years"), `year` (a calendar year: "2030"), `multiple` (of 2024's rates: "as now", "+20%"), `pence` ("52.95p"), `count` (a plain number) |
| `per` | What an amount is for: `"a car"` reads "£2,500 a car" |

An **indicator** has `row` (a national result row, a leading `-` showing it negated),
`icon`, `size` (default 2) and `better` (`"high"` or `"low"`, which tints its rises and
falls and the bars of "In a year"; empty where neither is clear); it may carry `unit` as a
policy does. An indicator whose `row` the model lacks is dropped.

A lever that no policy places and that is not hidden gets a policy of its own (the middle
tier, with the generic pictogram) in the area named by its `group`, added at the end of the
board if no area has that name ("Other" for a lever with no group), so a mod's levers are on
the board.

The UK scenario (`models/uk/scenarios/2025.toml`) has ten areas, 43 policies (38 in force
at the start), 33 indicators and 23 groups in six families; its comment block documents the
table in place.

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
layout). Version 1 added the cells; a version 0 file still loads, and its breakdowns by
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
`reload_model`, and from stage S13.1 `request_forecast`, `request_effects` and
`request_records`) go to a worker thread in order; `poll()` returns what has finished, as
dictionaries with a `kind` key. Everything the screen reads (`latest`, `previous`,
`pending`, `series`, `changes`, `hashes`, `catalogue`, `play_settings`, `cells`) comes
from a mirror the worker refreshes after each request, so reading never waits for the
simulation. No Godot object is touched off the main thread.

Stage S14.3: the worker sends the mirror only what changed: after a month, that month's
results (appended to the history and the changes the mirror keeps) and the latest and
previous values; after any other request, the changes waiting; after a load or a reload,
everything. A request costs the same in the first month and the hundredth, and every
reading returns what it did before. `is_busy()` counts the requests on the worker;
forecasts and the effects table run on threads of their own and are not counted, so
"Next month" never waits for them.

Stage S7.1: `open_with_mods(scenario_path, mods)` opens a scenario with mods the player
chose; `scenarios(base)` and `mods(folders)` list what the start screen offers, read
without opening anything; `active_mods()` and `mod_notes()` describe the game in play; the
`loaded` event adds `missing_mods`, and, when the save was made with other model files,
`migrated` with what was `carried`, `reset`, `clamped`, `dropped` and `renamed` (stage
S7.0).

Stage S5.4: the catalogue says whether the model has a `legislature`, and each lever's
`leaning`; `changes()` gives each policy change's vote (`passed`, `votes_for`, `seats`).
A policy's popup then says that changes are bills; a defeated bill is announced after
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

## Looking ahead (stage S13.1)

A look ahead runs an in-memory copy of the game (a fork: `Session::fork`, a copy of the
run with tracing off and no history kept) and never touches the game itself. In a fork,
the lever changes waiting and those asked about are **applied directly** at the first
month: not voted on and not charged political capital, since the question is what a change
would do if it passed. Commands scheduled for later months run as in the game. A fork never
answers a dilemma: one open, or opening on the way, stays unanswered, as the model runs it
when nobody answers. A month that fails gives the error, never a crash.

Events from these calls carry both `kind` and `type` (the same value).

| Call | Answer |
|---|---|
| `request_forecast(changes, months, tag)` | A `forecast` event: `tag`, `months`, `rows` (every result row, as `latest()` names them, to `[as_is, changed]`), `cells` (every one-dimensional value of at most 64 cells to `{as_is, changed}`, each a `PackedFloat64Array`) and `error` ("" when it ran). "As is" is the game with the changes already waiting; "changed" adds `changes` (lever name to value as typed), replacing any waiting change to the same lever |
| `request_effects(levers, months)` | One `effects` event per lever, in the order they finish: `lever`, `step`, `rows`, `cells` and `error`, each against one shared "as is" branch; then `effects_done` with `count` |
| `request_effects_first(first, levers, months)` | Stage S14.3: as `request_effects`, starting with the levers of `first` that are also in `levers` (the policy under the pointer), then the rest in order |
| `reach(from)` | Stage S14.3: at once, from the catalogue: every value a change in `from` reaches through the model's formulas, nearest first, as `{name, lagged}` (`lagged`: the route found passes a lag or `prev()`, so the change shows there a month or more later). Readers are found from each entry's `inputs` and then `lagged_inputs`, in catalogue order. Empty for an unknown name |
| `path(from, to)` | Stage S14.3: at once: a shortest chain from `from` to `to`, both ends included, each reading the one before it, as `{name, lagged}` (`lagged`: the link into it is through a lag). Empty when `to` cannot be reached |
| `vote_preview(lever, value)` | At once, from the mirror: `bill`, `votes_for`, `seats`, `passes` (the vote would carry), `cost` (-1 without political capital or when the change is no bill) and `affordable` (the capital less what the bills already waiting would spend before it, in the order they were made, covers the cost). Empty when the lever or value is not valid |
| `request_records(entity, where_row, count, columns, tag)` | A `records` event: `tag`, `records` (each `id`, `weight` and the latest value of each of `columns`) and `error`. Up to `count` records for which `where_row` is true (a per-record true/false value, or a formula of the entity's values; "" for all), every k-th of those that match, so the same request gives the same records. Unknown names give an error naming them |

**The step of the effects table.** A real lever, or a money lever, with a finite range
moves by 5% of the range; one without a range by 5% of its value (1 if it is 0); any other
whole-number lever by 1; each downwards instead when up would pass the top. A true/false
lever takes the other value. `step` is the signed move in stored units (money in minor
units; 1 or -1 for true/false). Levers the player cannot set (`player = false`, dilemmas,
what bills spent) come back with an `error` saying why.

**Staleness.** The table is computed off the worker, two levers at a time, so the next
month never waits for it. A month, a load, a reload or a new table makes it stale: the
computation stops at the next lever and nothing more of it reaches `poll()`. On the UK
model a 12-month forecast takes about 0.3 s and a 12-month table of every lever about 8 s.

**Stage S14.3.** A forecast runs on a thread of its own. The newest request wins: an older
forecast, or one of a game since stepped, loaded or reloaded, stops at its next month and
sends no event (a lever change does not stop it; the client asks again after one). The
effects table runs on every core but one (at most 16), stops at the next month (not the
next lever) when stale, and waits between months while a forecast runs, so the forecast
comes first. A lever change (`set_lever`, `cancel_lever`) changes the "as is" branch, so a
table asked for since the last month starts again at once with that lever first; its
`effects_done` still comes. A forecast and the table of the same game share their "as is"
branch: a forecast after the table has run only its changed branch. A save keeps the last
complete table of the game as it is (session file version 5); loading it sends its
`effects` events and `effects_done` straight after `loaded`, so the board has its links
from the first frame. An older save loads without one.

## Lever inputs and political capital

A lever's optional `group` (a name) is its policy area (stage S12.1) when the scenario
does not place it.

Money is typed in major units and rates in percent, as the policy popup describes. A policy
the scenario describes with `levels`, `unit` or `per` is held in its lever's catalogue
entry as `levels`, `show_as` and `per`, which `format.gd` reads so that every screen says a
value the same way.

With **political capital** (format 1, stage S12.4) the catalogue gives `capital` and
`capital_spent` (the state and the lever, "" without capital). The bridge's
`bill_cost(lever, value)` applies the engine's formula to the lever's current value (-1
when the change would be no bill), and `changes()` gives each change's `cost` (-1 for none)
and `refused`; saved games keep both (session file version 4). The client shows the capital
at the centre of the board and, on a wide window, in the top bar; shows each waiting
change's cost in its popup; and reports a bill refused for want of capital.

## How the client is tested

`tools/check_client.py` runs twenty scripted sessions in Godot without a display. The first
two compare state hashes with the command-line runner's; the others check what the screen
shows against the model, the runner or published figures. `board_check.gd`,
`capital_check.gd`, `forecast_check.gd`, `people_check.gd`, `policies_check.gd`, `full_term.gd` and
`feel_check.gd` also fail on any script error. The checks reach the screen through the
methods of `main.gd` listed after the table, as a player would.

| Script | Checks |
|---|---|
| `tests/scripted_run.gd` | 60 months through the bridge with lever changes: the same state hash as the runner on every step |
| `tests/ui_run.gd` | The same through the interface's controls (typed values, button presses), with a save, an unchanged reload and a load along the way |
| `tests/reload_run.gd` | A typo in a model file is reported and the game carries on; a real change takes effect the next month |
| `tests/situations_check.gd` | Stage S7.3: in `2025.toml`, no situation after a quiet first month; then, with health spending cut by about a third, a recession: announced, and shown as a flag with the month it began |
| `tests/dilemma_check.gd` | Stage S9.1: Valmora with the dock strike mod: a year's run stops at the third month and asks; no month runs until answered; the answer shows as a flag and raises the government's purchases by a fifth; then the same in French |
| `tests/lag_check.gd` | Stage S10.5: Valmora with the year-on-year mod: the catalogue marks the lag and its twelve states; the board's search links the lag to output as one lagged input; after fourteen months the lag holds the second month's output; its popup's "why it moved" follows it to output's popup |
| `tests/language_check.gd` | Stage S7.4: from the start screen, French is not offered for the UK; Valmora in French has a French Budget and policy popups, and so does a game saved and loaded |
| `tests/start_screen.gd` | Stage S7.1: started without a scenario, the start screen lists the United Kingdom and Valmora and offers the example mod (`mods/wealth_tax`) for the UK only; with it ticked, the game starts with the mod's lever on the board, its name in the title bar, and, once the rate is set, a wealth tax line in the Budget |
| `tests/migrate_check.gd` | Stage S7.0, run twice on a copy of Valmora: a game saved after four months with the basic rate at 30%; then, with the model's files changed (a new state, the basic rate limited to 25%), the save loads, the rate is at 25%, the player is told, and the next month runs on the new model |
| `tests/second_model.gd` | A model with different names (`models/mini`) gets a working Budget, an automatic board with two policies, two headline figures, and a lever change that reaches the Budget |
| `tests/politics_check.gd` | Stage S5.5, run twice: in `2025.toml`, after a month Parliament shows the 2024 House (411 centre-left seats and the rest), the government's poll rating and the next election in July 2029; in `early_election.toml`, the election in the second month is announced, the player has lost office, and advancing no longer moves time |
| `tests/web_walk.gd` | Stage S6.1, through the board: the shortest chain of the model's own connections from the basic rate to the government's poll rating, walked back from the rating's popup by following each cause, each step opening that value's popup, and Back |
| `tests/bill_vote.gd` | Stage S5.4: in the UK's hung-parliament test scenario the player's coalition raises the basic rate through its popup and is voted down 324 to 326: the rate keeps its value, the change is recorded as defeated, the player is told, and the chart marks nothing |
| `tests/capital_check.gd` | Stage S12.5: after a month the capital shows; a basic rate of 22% costs 6.2; two big bills in one month leave the second refused, and the player is told |
| `tests/board_check.gd` | Stage S13.2: the UK board is built from `[play.web]` with exact counts (the policies in force, those not in force kept off it and counted on their areas' `introduce` nodes, the indicators, and 23 groups in six families, each family together, the estimated groups last); every lever is on the board or available to introduce; no two nodes, no label shown at rest and no four flags overlap at 1366x768, 1920x1080 and 2560x1440; every node is labelled at rest at the two larger sizes, and at least 90% at the smallest; every node kind opens the right popup (the centre opens Parliament); a basic rate typed in Income tax's popup waits with its cost; pointing at a policy shows links, none passing under the centre; the Budget's lines open popups. Then `models/mini` gets an automatic board |
| `tests/forecast_check.gd` | Stage S13.3: after a month a basic rate of 21% shows, under "In a year", income tax up and household income down, and the Commons vote line says it would pass; once the effects table has arrived, Income tax's links are measured and point the way the table has the rate move them; a VAT rise typed after an expensive income tax bill says there is not enough capital |
| `tests/people_check.gd` | Stage S13.4: after three months a group's popup shows the model's approval and drivers; Northern Ireland shows a dash; eight households are shown for a group, each in it, and a household's account adds up to its net income; a basic rate of 21% lowers high incomes' approval by more than low incomes' in "In a year"; pointing at Income tax links the budget balance and unemployment, both up. Valmora, which has no groups, gets a board with an empty middle |
| `tests/policies_check.gd` | Stage S13.5: each area's list holds exactly its policies not in force; the new indicators have figures; the electric car grant introduced at £2,500 shows the electric share up and the balance down, puts a ghost on the board and spends capital, is in force after the month and in the report, and leaves the board when repealed; a level policy offers its named levels and stores the level chosen; the drinking age reads in years and raising it lowers the young's approval in a year; a higher fuel duty shows motorists against and receipts up, and pointing at it links motorists; an unaffordable introduction is refused, its ghost goes and the notice says why; an estimated group's popup says so and shows no households |
| `tests/full_term.gd` | Stage S13.6: all sixty months of the UK's term played through `main.gd`'s methods with nineteen decisions (taxes, spending, three introductions, level policies, a repeal), every question answered, each kind of popup and both sheets opened; no month fails; each bill's fate is what the report and the notices said, a third bill in one month is refused for capital, and capital adds up and never goes below zero; the election comes in July 2029 and its result is announced; a game saved in month 24 and loaded gives the same state hashes to month 36 |
| `tests/feel_check.gd` | Stage S13.6: at step 0 every figure shows the awaiting state, and every popup kind and both sheets open with no "nan"; no change too small to show reads as a signed nought; the guide is wanted on a first game from the start screen, never with `--scenario` or headless, and its steps point at real things; a bill refused for want of capital and one passed appear in the report with the figures that moved most, and Space ran that month; the links of a node held under the pointer while the table arrives change at most once; B, P, Esc and H do their jobs, and Space does nothing in a focused field; a game from the start screen opens with its first month played; the sound helper asks for its sounds and makes no player headless |
| `tests/budget_dump.gd` | The UK's Budget after one month, read as text and parsed back: every line within 1% of the 2024 public finances in `models/uk/data/annual.csv` (totals, shown to three figures, within 0.6%), and no input marked `player = false` among a policy's controls. Then every breakdown, as shown in the popups of the figures they break down, after that month and after a second with the basic rate one point higher: every group shown with its label; all households' net income equal to the runner's to the pound; the rise taking from the fifth decile up, from each of the top three at least £100 a year more than from the poorest, and from every region but Scotland, which sets its own rates |

**What `main.gd` offers the checks.** Actions: `open_node(key)` (a board key, an
`introduce:<area>` node, or the key of a policy not in force), `open_indicator(name, row,
origin)`, `open_overlay("budget" | "parliament")`, `close_overlay()`, `close_popup()`,
`type_lever(lever, value)` (into the policy's popup, opened if need be, as a person types),
`hover(key)`, `introduce_policy(key, value)` (opens the popup of a policy not in force, picks
the setting and presses **Put to the Commons**; returns the bill's text, or "" if none was
put), `repeal_policy(key)`, `open_introduce(area)`, `advance(months)`, `answer_dilemma(name,
answer)`, `menu_action(action)`, `set_ui_scale(choice)`, `set_volume(volume)`,
`show_guide(remember)` and `show_per_year(on)`. Readers: `popup_kind()`, `policy_card()`,
`group_card()`, `indicator_card()`, `introduce_list()`, `current_trace()`, `overlay_open()`,
`board_levers()`, `available_policies(area)`, `latest_value(row)`, `previous_value(row)`,
`flag_text(key)`, `capital_text()`, `title_text()`, `notice_text()`, `notice_visible()`,
`dilemma_title()`, `unanswered_dilemmas()`, `can_advance()`, `awaiting()`, `guide_steps()`,
`guide_seen()` and `situation_onset(row)`; and the cards' own fields (for the policy card,
`year_shown`, `year_groups` and `draft`; for the group card, `records`, `drivers_shown` and
`approval_text`). The board's `nodes`, `available`, `effects`, `links_for(key)`,
`linked(key)` and `overlaps()` are read directly.

`tests/screens.gd` saves screenshots of a scripted Valmora session
(`--scenario=models/valmora/scenarios/term.toml`, `--shots=DIR`). `tests/look.gd` saves one
screenshot of any scenario, for a person to look at; it needs a display (on a server,
`xvfb-run`), and Godot's `--resolution WxH` before `--path` sets the window size. Its
options, after `--`:

| Option | Effect |
|---|---|
| `--scenario=PATH` | The scenario; without it, the start screen |
| `--months=N` | Play N months first, answering any question with its first answer |
| `--shot=FILE` | Where the picture goes (default `user://look.png`) |
| `--node=KEY` | Open a node's popup: `policy:income_tax`, `indicator:gdp`, `group:pensioner`, `introduce:Transport`, `centre` |
| `--entry=NAME` | Open any value's popup by catalogue name |
| `--overlay=budget` or `parliament` | Open a sheet |
| `--hover=KEY` | Point at a node, so its links show |
| `--effects=1` | Wait for the effects table first, so hover links are measured |
| `--type=LEVER:VALUE` | Type a change into the lever's policy popup (closed again unless `--node` is given); `--then=N` plays N more months |
| `--introduce=KEY:VALUE[,KEY:VALUE]` | Introduce policies not in force (`--then=N` plays on) |
| `--draft=KEY:VALUE` | Open a policy not in force with that setting picked, and wait for "In a year" |
| `--household=N` | With a group node, open its Nth household's account |
| `--dilemma=1` | Leave the question on screen |
| `--report=1` | Show the month's report |
| `--guide=N` | Show the guide's Nth step |
