# The game client (stages S2 to S15)

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
| `client/scripts/web.gd` | GDScript | The board: layout, nodes, the group ring, links, gauges, the automatic board |
| `client/scripts/strip.gd` | GDScript | Stage S14.1: the strip under the top bar: the notice line and the situations' pennants |
| `client/scripts/key_page.gd` | GDScript | Stage S14.1: the key, drawn by the board's own code |
| `client/scripts/popup.gd` | GDScript | The one popup, which grows from a node and has Back |
| `client/scripts/lever_panel.gd` | GDScript | A policy's popup: controls, cost, vote, "In a year", history |
| `client/scripts/add_policy.gd` | GDScript | Stage S15.1: the Add policy sheet's content: the areas, and each area's policies not in force with cost, vote, cheer and boo (it replaces `introduce_list.gd`) |
| `client/scripts/search.gd` | GDScript | Stage S15.1: the search field on the top bar, its index and its list of matches |
| `client/scripts/indicator_card.gd` | GDScript | An indicator's popup (also a budget line's, a top-bar figure's, a situation's) |
| `client/scripts/group_card.gd` | GDScript | A group's popup and a household's account |
| `client/scripts/sheet.gd` | GDScript | A sheet laid over the board: the Budget, Parliament, a question, election night, help, the key |
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

The window holds the top bar, the strip under it (34 pixels, always there) and the board
below them, and over them at most one popup and one sheet, the month's report and the
guide. Nothing else. Only the window's size changes the board's: the report, the notices
and the popups float over it (stage S14.1).

**The top bar.** From left to right: the country (with the mods in play) and the month; a
button for each of the first six values of `[play] headline` (or of `watch` when there is
no `headline`), showing the value and its change on last month, which opens that value's
popup; the search field (stage S15.1, [Search](#search)); **Add policy** ([The Add policy
sheet](#the-add-policy-sheet)); a status line; **Next month**, **3 months** and **Year**;
**Budget** and **Parliament**; "?", which opens the key; and **Menu**.

**What gives way on a narrow bar (stage S17.1).** The bar never needs more room than the
window has, and what gives way as the window narrows does so in a stated order, each step
only when the one before was not enough: first the words on **Budget** and **Parliament**
(their pictograms stay) and on **3 months** and **Year** ("+3", "+12"); then the search
field, from 190 pixels to 150 and then to its button, the magnifier alone (it opens to type
in, with "/", Ctrl+F or a click, and shuts again when it loses the keyboard empty; while
it is open the figures give way to it); then the headline figures, one at a time, least
important first: in the order of `[play] give_way`, then any that names not, from the
right (each is still on the board or in the Budget); last, Add policy's words. Approval and
political capital never give way. On the UK three months in, the words go at about 2,130
pixels, the search field shuts at about 1,900, and the figures go at about 1,790 (GDP),
1,680 (debt), 1,570 (inflation), 1,480 (unemployment) and 1,340 (the budget balance): at
1920 wide every headline figure shows. The smallest window is 1,200 pixels wide (1,100
before: the bar's fixed parts alone need about 1,170). The country's name is cut short with
an ellipsis at the width of the month under it (its tooltip has it whole, with the mods).
`main.bar_state()` says how far the bar has given way. Pressing the month opens the last month's report
again (or closes it). A `headline` name with a leading `-` is shown negated. A
figure's label is `[play] labels[key]`, else the catalogue's. Approval and political
capital lead the top bar (stage S16.1; S14.1 had taken them off as doubles of the centre,
which the owner called a big error): capital with what the bills waiting will cost ("bills
waiting N"), or, in red, how far short it is when they cost more than there is ("N short",
alone since stage S17.1: both figures together pushed a headline figure off a 1920-pixel
bar; the tooltip has the rest). They never give way,
and the bar is drawn above every popup's and sheet's veil. The centre of the
board shows both as well.

**The strip** (`strip.gd`). At its left, under the date, one line: a notice (6 s), an
ordinary month's news (3 s) or a problem (in red, until clicked; a click on a notice of
several lines opens the whole of it). At its right, the flags in force as pennants: each
situation, a question waiting ("Decide: <label>", ochre) and each answer while it lasts
([Situations](#situations), [Dilemmas](#dilemmas)). Pointing at a pennant says since when
and gives its `doc`; a click on a situation's lights its statistic and opens the situation
(stage S15.1), and a click on a question's asks it. The pennants are rebuilt only when they
change.

**The menu.** Save, Load, Reload model; "Amounts a year" (a check item: flows at an annual
rate or per step); "Size of the screen" (Automatic, 100%, 125%, 150%, 175%, 200%); Sound (a
check item) and Volume (25%, 50%, 75%, 100%); "Show the guide again"; "The key"; Help. The
screen size is `ui/scale` in `user://settings.cfg` (0 for automatic: the window's height
over 960 pixels, rounded to a quarter and held between 1 and 2, applied as the window's
content scale); sound and volume are kept there too. Help is a sheet with the essentials
and the credits for icons, type and sounds.

**The key** (`key_page.gd`, stage S14.1). A sheet, opened by "?", K or the menu: one row
each for policies, indicators, groups of voters, links and situations, each with a sample
drawn by the board's own code (small boards in demo mode, `web.gd`, and the strip's
pennants), so it cannot drift from the board; the groups' row states the scenario's
`approval_good` and `approval_bad` and the gauge's full mark.

**Keys.** Handled by `main.gd` unless a text field has the focus or the guide is open:
Space, Enter or Keypad Enter, next month (not while a question waits); B and P, open or
close the Budget and Parliament; A, open or close the Add policy sheet (stage S15.1); "/",
focus the search field and select its text; K, open or close the key; Esc, close the popup,
else the month's report, else the topmost closable sheet. Ctrl+F focuses the search field
too. In the search field the arrows move between matches, Enter
opens the chosen one and Esc clears the search and leaves the field. No key moves the
board.

**The keyboard inside a popup or a sheet (stage S17.1, `focus.gd`).** Opening one takes the
keyboard into it: to the card itself, so nothing wears the ring until Tab is pressed. Tab
and Shift+Tab then go through its controls in the order the card is built (top to bottom,
left to right) and round again, never out to the board or the top bar behind; what the
keyboard reaches is scrolled into view. Esc closes the topmost thing (a popup over a sheet
before the sheet) and the keyboard goes back to whatever had it: the button that opened
the sheet, the Budget line that opened the popup. So a popup opened from the search
closes first and leaves the search as it was; Esc there then clears it. Whatever holds the
keyboard shows it: a ring 2 pixels wide, 3 clear of the control, in `Palette.FOCUS` (the
dark ochre that text waiting is set in, 4.5 to 1 on card stock and on the paper; plain
ochre was 2 to 1), the same on buttons, links, fields, sliders, menus and text that can be
selected; a check box wears it as its own outline. The row chosen in a menu or among the
search's matches has an ink edge down its left as well as its tint. The pictures on the key
are not controls and the keyboard passes them by.

**The month buttons** are off while the game is busy, while a dilemma waits (their tooltip
then says to answer it first) and after the player has lost. Advancing asks the engine at
once, then closes the popup, the report and the notice line, and records what the report
will compare with. A month asked for
while the engine is finishing something else is queued and runs as soon as it is free,
never dropped.

## The board

Stage S13.2. `web.gd` is one `Control` filling the window below the top bar and the strip,
drawn in layers (the rings, area names and families' names; the links; the nodes and their
effects) so that pointing redraws only what moved, and a layer is redrawn only while
something on it moves (stage S14.1): a link drawing in or fading, a node lifting, a pulse,
the links' flow while the pointer is on a node. With a popup open and nothing happening,
nothing is redrawn. The layout is authored and stable: nodes are placed by rule from the
scenario's `[play.web]`, never by simulation.

**Fixed** (stage S14.1). The board is the screen. It cannot be dragged or zoomed: a drag
and the wheel do nothing, and no key moves it. It fills the room it is given and nothing
docks beside it. It is laid out again only when the window's size changes, when the
groups' shares are first known, and when a policy comes onto the board or leaves it (the
nodes then glide to their new places over 0.3 s). Sizes scale with a unit,
the smaller of the width over 1.55 and the height, over 800 pixels, held between 0.72 and
2.2.

**Rings.** Concentric ellipses, wider than tall, fitted to the window, and a circle for the
groups.

| Place | Nodes |
|---|---|
| Outer ring | Policies, in an arc for each area, in the order `[[play.web.areas]]` lists them, with the area's name set along the rim outside. An area's share of the ring is what its policies need, or what its indicators need on the middle ring over the same angle, whichever is more. Where the first area begins is tried at up to eleven places round the rim (`START_TURNS`: five from stage S14.5, eleven since S15.3) and the first that labels every policy and indicator at rest is kept, else the one that labels most. The rim holds only policies in force (and ghosts): since stage S15.1 there is no "New policy" node; the policies not in force are on the Add policy sheet |
| Middle ring | The indicators of each area, in that area's sector; down the sides, a sector too narrow for them in one row puts every second one in a second row on an inner ring, between the first row's nodes; above and below the group ring an area takes more of the rim instead |
| Group ring | Stage S14.4: one circle round the centre, as large as the indicators allow. Each group is an arc of it ([below](#the-group-ring)) |
| Centre | One medallion, filling what is inside the group ring (radius 58 to 120 pixels at a unit of 1) |

A board with more nodes than its rings hold draws them smaller, to two thirds of their
size at least, and never overlapping.

**Labels.** Every node that has room for one gets a label at rest, the largest nodes first
(indicators before policies of the same size, the groups last). Policies label towards the
centre, indicators outward, then below; each tries a wide label, then one on two lines,
then the other places round the node, and takes the first that clears every node, the
group ring, the rim's area names and the labels already placed; up to three rounds of
repair then place a failed label first among its neighbours, kept only if all still fit.
The largest nodes have the larger type. The groups' names, each just outside its arc, are
shown at rest only when every one of them fits, else none (a group pointed at shows its
own). A policy's label on the board is `[play] labels[<policy key>]` when the scenario gives
one (stage S15.3: "Police and courts" for "Police, courts and prisons"), unless a result row
has that key; its popup keeps the whole name (the node's `long_label`). A node lit by search
or a situation shows its label too, and while a search matches six nodes or fewer, so do
they.

<a id="the-group-ring"></a>**The group ring** (stages S14.1 and S14.4). Each family takes
room for its number of groups, apart from the next by a gap of 16 pixels (3 between two
groups of a family); the first family is centred at the top, and each family's name is set
once along the inside of the circle. Within its family, each group's arc is as long as its
share of the electorate (`share`, taken once, when first known, so the ring never shifts
from month to month), and never shorter than 1.02 times the band's thickness (`ARC_LEAST`,
stage S15.3: room for its pictogram, set square). The band is 34 pixels thick at a unit of
1 (about 42 at 1920x1080). Stage S15.1: when the ring cannot hold every group at that
thickness inside the room the indicators leave, the band thins until every arc still takes
its least length, never below two thirds of its full thickness; `board_check.gd` proves a
ring of thirty groups in seven families at 1366x768. Stage S15.3: every family is named
once; a family name longer than its family's arc takes room from its neighbours', the names
being pushed apart round the ring until none overlaps (if together they are longer than the
ring, none is set). Just outside each arc, 3 pixels off, runs its
approval as a gauge 7 pixels thick (9 at 1920x1080): a pale track filled from the arc's
start in proportion to approval, full at 60% (`APPROVAL_FULL`), green from
`approval_good`, red under `approval_bad`, mustard between, grey with no figure. A group
is pointed at and clicked anywhere on its band and gauge.

**Node kinds.**

| Kind | Shape | Size | Gauge and marks |
|---|---|---|---|
| `policy` | Disc with a pictogram | Three tiers, from `size`: radius 17, 22 or 29 pixels at a unit of 1 | A gauge arc over three quarters of a circle from the lower left: where the first lever's value sits between its minimum and maximum (when the maximum is more than four times the starting value, and the minimum is nought, the top is twice the starting value). A short ochre line on the gauge marks the change waiting, and an ochre dot on the node says one is waiting on any of its levers. A policy to be introduced, its bill waiting, is a ghost: dashed edge, faint pictogram, no gauge |
| `indicator` | Ring with a pictogram | The same three tiers | Its colour says what kind of thing it measures and never changes in play (stage S14.1): green for a good thing (`better = "high"`), red for a bad thing (`"low"`), blue for the rest. A triangle on a small badge for last month's rise or fall, green or red where `better` says which is good and ink where it does not; a pulse after a month in which it moved by at least 0.1 points (a rate) or 0.5% |
| `group` | An arc of the group ring with a pictogram | The arc's length, as above | The approval gauge. A group with a `note` and an approval of nought shows a dash and a grey gauge |
| `centre` | Large medallion | | The government's approval, its change, the months to the election, and the political capital with what bills waiting would spend; a line too wide goes on two |

The `introduce` kind (a dashed disc with a plus, "New policy", at the end of an area's arc)
was removed in stage S15.1.

The centre's approval is `[play.politics] support` (else the first headline value).
Questions and answers are pennants on the strip only ([The screen](#the-screen)). A
situation in force is a pennant on the strip and also, since stage S15.1, a small pennant on
a staff at the upper left of the statistic it belongs to ([Situations](#situations)), one
per situation, green for a good one and red for a bad one (`node_flags`).

**Search and lighting** (stage S15.1). While a search has text, every node that does not
match (but the centre) is drawn faint, and the match chosen in the list is lit. A lit node
(`light(key)`, also used by a situation) wears a broad ochre ring with an ink hairline
outside it, drawn under the labels, and pulses once.

**Links.** Only the node under the pointer (else the selected node) has links drawn; the
rest of the board dims at once, in one redraw, and the links draw in over about 0.15 s.
Leaving a node waits 0.15 s, so crossing a gap does not blink the links. A link has a
direction (an arrow from cause to effect), a tone, a sign and a strength (the line's width
and the flow of its dashes). Its tone says whether the effect is good for what it reaches
(stage S14.1): green when it moves the target the way its `better` wants (for a group,
approval up), red when the other way, blue when the target has no `better`, and grey for a
link read from the formulas, not measured. A small square of card by the arrowhead holds +
(the target rises) or - (it falls), so colour never carries the direction.

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
  `lagged_inputs`), drawn grey at one strength. A ghost has no links. This search is the
  board's own (`reaches`), not the bridge's `reach`: it stops at the first node shown along
  each route, which `reach` does not.
- An indicator's or a group's links come from the policies that move it most, the same
  table read the other way, seven at most.
- While the table arrives for a node held under the pointer, its links change at most once,
  from the formulas' to the measured; measured links already shown stay until the pointer
  moves on.

**The effects table.** After a game opens and 0.3 s after each month (later if the engine
is busy), the client calls `request_effects_first(first, levers, 12)`
([Looking ahead](#looking-ahead-stage-s131)) for every lever of a board policy, and (stage
S15.1) the first lever of every policy not in force, not yet measured this month, `first`
being the levers of the policy open in a popup, else of the
policy under the pointer. A pointer resting 0.25 s on a policy not yet measured while the
table runs asks again with that policy first. For each lever the client keeps, for each
row, the change as a share of the as-is value (ten times the change in the rate, for a
rate), signed as for a rise when the table had to nudge the lever down. The last table's
values stay in use until the new month's replace them lever by lever; a table the bridge
restarts by itself after a lever change is taken as it comes. While the table runs, a
node pointed at whose links are not all measured says "measuring its effects…". A loaded
game gets the table kept in its save straight after `loaded`, so nothing is asked for
until the next month.

**Pointing and selecting.** Pointing sets the hover, which the links follow, and lifts the
node; a click on a node opens its popup and selects the node while the popup is open. The
pointer leaving the board, or a popup or sheet opening over it, clears the hover. The
focused node's label sits on a tag with its value and change under it.

**What a node says.** After each month the client sets every node's value, change and trend
and pulses those that moved notably. A policy's value is its lever's value as the policy's
`levels`, `unit` and `per` read it; one whose repeal waits says so. A group's state is its
approval's `good`, `mixed`, `bad` or `none`. Stage S14.1: an engine event refreshes only
what it changed: a month refreshes the screen (during a run of months only the date
follows each month, the rest once the run ends); the effects table, a forecast, an
explanation or households touch only their own panel.

**The automatic board.** A scenario with no `[play.web]` gets a board made from the model:
one area for each lever `group`, in the order the model names them (levers with none go to
"Policy"); one policy for each lever, of the largest tier when the model has twelve levers
or fewer and the middle one otherwise, with a generic pictogram; the `headline` and `watch`
rows as indicators (the largest tier for a headline row, the middle one for the rest), each
in the sector of the first area whose levers reach it through the formulas, or of the area
with fewest indicators; no groups, so the middle is empty. Nothing is hidden and nothing can
be introduced.

## Popups

`popup.gd` shows one popup at a time: a card 640 pixels wide, one column, sized to what it
holds, that grows from the node, top-bar figure or budget line that was clicked, closes
faster than it opens, and dims the board, which then ignores the pointer. Esc or a click
outside closes it. Following something inside it (a cause, a policy, a group) replaces its
content and offers **Back**; a section opened inside asks it to fit again. At 1920x1080 no
popup needs a scroll bar. `main.popup_kind()` names the kind open: `policy`, `indicator`
(also a situation's), `group` or `household`, and `add_policy` while the Add policy sheet is
open (the `introduce` kind went with the "New policy" node in stage S15.1).

**Policy** (`lever_panel.gd`). The area, the policy's whole name (`long_label`), and its lever's `doc` when it has
one lever. It opens with its main controls (stage S14.1): its first lever, and any rate
among its first three (Income tax's three rates, not its thresholds); the rest wait under
**More** ("More: " and their names, or "More: N further settings"). One control for each
lever, with its setting now and any change waiting (ochre, with **Undo**):

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

*In a year.* Under the controls stands the policy's history chart, with the player's changes
marked; once a control has moved, "In a year" takes its place (stage S14.1). With a change
waiting in the policy's levers, 0.05 s after the last edit (stage S14.4; a newer forecast
stops an older one in the bridge) the client calls `request_forecast` over 12 months with
the policy's levers at their present settings. "As is" is then the game with all the
changes waiting, and "changed" the game with this policy's change taken out, so the table
reads as what the change adds. While it runs the last figures stay, greyed, under a small
"measuring" mark; afterwards the heading names the setting ("at £2,500 a car",
"repealed"). The rows are the budget balance first;
then up to three lines of the Budget and up to six indicators on the board, taken in the
order of how far each moves for its size (a rate against at least two points, else a share
of its value) weighted by the square of its tier; then, under "The groups it moves most",
the five groups whose approval moves most, in points. A bar is sage where the board's
`better` calls the change good and brick where bad, ink where it says nothing. Each name
opens that indicator's or group's popup. A policy not in force and one with `levels` have
no history chart.

*Introducing and repealing* (stage S13.5; the sheet, stage S15.1). A policy is in force
when its first lever is not at its `off` setting. A policy with an `off` and one lever, not
in force, is available: off the board, and offered by the Add policy sheet
([below](#the-add-policy-sheet)). Choosing one there closes the sheet and opens its popup,
"not in force", set to the smallest step in (the next level, else a tenth of the range,
towards the other end when that would pass the top) as if picked, so its cost, vote and
**In a year** show at once; another setting may be picked, and nothing is sent until **Put
to the Commons** ("Bring it in" without a legislature). The bill stands as a ghost until the
vote; when the lever leaves its `off` setting the ghost grows onto the board and the policy
leaves the sheet. A policy in force with an `off` has **Repeal**, which sends the `off`
setting as a bill and shows its cost and vote; when it passes, the policy leaves the board
and is available again. An `off` on a policy of several levers is ignored.

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

**Situation** (`indicator_card.gd`, stage S15.1). A situation's own popup, opened by its
pennant, its line in the report or search, never by a chart of noughts and ones: "In force"
or "Not in force", "since <month>" while in force, its `doc`, and **Set off by**, the label
and value now of the statistic it belongs to, a link to that statistic's popup. It grows
from that statistic's node, which is lit; a situation with no node opens under the strip
and has no "Set off by". It has no "Why it moved".

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
place. Stage S15.3: a belief group (the `low_group` or `high_group` of one of `[play.web]
stances`) says under its approval which stance it reads and where the government stands on
it ("Where the government stands, for them: Liberty against order, 1.0 toward order (they
want order)", or "where it stood in 2024" within 0.05 of nought), and opens with **What is
moving them** unfolded.

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
  approval and change, a row opening the group's popup. Stage S15.3, in folds: **Where the
  government stands** (open first when `[play.web] stances` has any, else "The parties"):
  each stance a scale, its label in capitals above with what moved it last on the right
  ("last moved by <policy>, <month>": the newest passed bill among the levers the stance's
  formula reads, from the catalogue), a line with ticks and nought in the middle, a marker
  at the stance's value, and each end's words with its belief group and that group's
  approval, under a note that each scale counts the government's clear moves of policy
  since 2024, net; and **The country by place**: a row for each of `[play.web] places`, with
  its share of adults, its backing for the government (or the `note` and a dash) and last
  month's change. In a month with an election a sheet gives the results (votes, seats,
  change) and the new government. When the player's bloc is out of government the game is
  over: time stops, and a saved game can still be loaded.
- <a id="the-add-policy-sheet"></a>**Add policy** (`add_policy.gd`, stage S15.1), opened by
  the top bar's button, A, a search result for a policy not in force or a report line
  about one: the areas down the side in board order, each with its pictogram and how many
  policies it has to add (greyed, with a tooltip, when none); for the area chosen (at first
  the first with something to add, or the area of the policy asked for, scrolled to its
  row), each policy not in force with its pictogram, its `line` (else the first sentence of
  its lever's `doc`), the smallest step's cost in political capital, the vote
  `vote_preview` gives it ("Would pass, N to M" or "Would be voted down", and "not enough
  capital"), and **Cheer** and **Boo**: the three groups whose approval the effects table
  has the smallest step raise most and the three it lowers most (moves under 0.0005 left
  out; "measuring…" while the table runs). The list scrolls when it is taller than the
  window leaves. Choosing a row closes the sheet and opens the policy's popup at that step.
  It is rebuilt each time it opens.
- A question (a dilemma), election night, Help and the key are sheets too.

<a id="search"></a>**Search** (`search.gd`, stage S15.1). A field on the top bar. Its
index, built once per model (and on reload), holds every policy, indicator and group on the
board, every policy not in force and every situation, each with the words it is found by,
in order: its label; its `also` words; its levers' names and labels, its model name and its
whole name; its `doc`. A query matches a thing when every word of it is found in one of
those; matches rank by the latest of those places any word needed (the label first), then
by whether the label begins with the first word, then by kind (policies, statistics,
groups, situations, policies to add). Each key typed runs the query on the index, with no
engine call. Under the field a list shows the first ten matches grouped by kind ("and N
more on the board" for the rest, "Nothing called that." for none); the board dims to the
matches' nodes (a situation's node is its statistic's) and lights the chosen one. The
arrows and the pointer move the choice; Enter or a click opens it: a node's popup, a
situation's popup on its node, or the Add policy sheet at a policy not in force. Esc clears
the field and leaves it.

**The month's report** (`month_report.gd`). After the months of an advance have run, the
report is filled; several months played at once give one report, headed with the first
and last month. It has up to five sections: *Bills*, each change put to the Commons since
the advance began, in words such as "Fuel duty to 62.95p a litre", "Electric car grant
introduced at £2,500 a car" or "Electric car grant repealed", marked passed, voted down
(with the count) or refused (with the capital it needed), with a note when one was voted
down or refused; *Situations* that began or ended; *Election*, a general election in those
months, whose line opens Parliament; *Decisions*, the answers given; and *Moved most*, up
to four board indicators and groups, ranked by the change against the value's own mean
monthly move before, tinted by `better`. Stage S14.1: it is a window 460 pixels wide over
the board, at its top left under the date, never beside it, and the board keeps its size.
It opens by itself only when there are bills, situations, an election or decisions to tell;
otherwise the strip's line says "<month>: " and the two largest moves (or "a quiet month")
for 3 s. It stays until closed (Close, Esc, a line clicked, the next month asked for) and
the date opens it again. A line opens its node's popup (a value off the board, its own
popup; a situation's line, the situation on its node; a bill about a policy not in force,
the Add policy sheet at it). A refusal or a defeat is told once, in the report, not also in a notice. Nothing is
shown after the base month when no bill was put.

## Situations

Stage S7.3. The model's situations ([model format 1](06-model-format-1.md#situations-stage-s73))
that are on are shown as pennants on the strip under the top bar (stage S14.1; before, flags
on the board), each with the month it began (from the history) and its `doc` as a tooltip:
green for a good one, red for a bad one (a situation is one or the other; blue is for an
answer in force, ochre for a question waiting); a pennant opens the
situation's popup. The situations that began or ended in the months played are listed in
the month's report. Nothing is announced for a game just opened, loaded or reloaded.

Stage S15.1: **a situation belongs to a statistic.** The client finds each situation's node
once per model, the first of: a field of the situation's catalogue entry naming a value
(`statistic`, `set_off_by` or `row_of`; none is set by the model format today); the
scenario's `[play.web] situations` table (situation name to a row or catalogue name); the
first value its condition reads (`inputs`) that is an indicator on the board. A situation
whose name finds none has no node. While it is on, its node wears a small pennant
([Node kinds](#the-board)); its strip pennant, its report line and a search for it light the
node and open its popup there, with "Set off by" ([Popups](#popups)). The UK maps all 25 of
its situations in `[play.web] situations` (strong growth and a recession to Growth, a wave
of strikes to days lost to strikes, and so on).

## Dilemmas

Stage S9.1. The catalogue lists the model's dilemmas ([model format
1](06-model-format-1.md#dilemmas-stage-s91)) with their answers, in the model's words or
the game's language. When a step leaves a dilemma open with no answer given for the next
month, the client asks it in a dialog: its `doc`, each answer's label and `doc`, and a
button for each answer. Choosing one sets the dilemma's lever to the answer's number, for
the next month. No month runs while a dilemma waits: the month buttons are off, and a run
of several months (a quarter, a year) stops at the month the dilemma opens, which the
bridge enforces on its own thread (`Session::unanswered_dilemmas`). The player may close
the dialog to look around; the ochre pennant "Decide: <label>" on the strip asks again.
Once answered, a blue pennant shows the answer, "from next month" until it applies, then
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
| `give_way` | Stage S17.1: the headline figures in the order they give way on a top bar short of room, the first first. The approval is never among them | from the right |
| `watch` | Values `polisim play` prints after each step; the top bar's figures when there is no `headline`; with an automatic board, indicators beside the headline's | none |
| `labels` | Overrides of labels by key, including negated keys such as `"-gov_money"`, for the top bar and the board. Stage S15.3: a `[play.web]` policy's `key` here gives that policy a shorter name on the board (the UK: `policing = "Police and courts"`); its popup keeps the whole `label`. A key that is also a result row's name is that row's label, not the policy's | none |
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

Stages S13.2 to S15.3. Read by the client only: the engine ignores it, so no model hash
changes with the layout. Names are catalogue names (levers, values) or result-row names as
noted; an item whose name the model lacks is skipped.

| Key | Meaning | Default |
|---|---|---|
| `hide` | Levers the player does not hold on the board (the UK hides Scotland's own income tax rates) | none |
| `approval_good`, `approval_bad` | Stage S14.1: the approval (a fraction) from which a group's gauge is green, and below which it is red; mustard between | 0.38, 0.28 |
| `situations` | Stage S15.1: a table from a situation's name to the row (or catalogue name) of the indicator it belongs to ([Situations](#situations)) | each situation's first input on the board |
| `also` | Stage S15.1: a table from any name (a situation's, a policy's key, a row) to a list of other words search finds it by; `also = [...]` on a policy, an indicator or a group entry does the same for that item (by its key, row and levers). The UK gives none | none |
| `stances` | Stage S15.3: Parliament's scales, a list of tables: `row` (a national value, nought at the start), `label`, `low` and `high` (the ends' words), and optionally `low_group` and `high_group` (the keys of the groups at each end, which the scales name with their approval and whose popups say they read this stance) | none: no scales |
| `places` | Stage S15.3: Parliament's "The country by place", a list of tables: `label`, `row` (approval), `share`, and optionally `note` (said in place of an approval of nought). The UK lists the seven regions that left the ring | none |
| `shelf` | Stage S15: statistics kept off the board but still reachable, a list of tables: `row`, and `see`, the statistic on the board that stands for it. Search lists them under "Not on the board" and Enter opens the indicator popup; the popup of `see` links to them under "See also". The UK shelves the nine statistics the S15.2 audit took off the board | none |
| `balance` | The result row a policy's links always include when it moves it | `budget_balance` |
| `group_share` | The value over the group dimension that gives each group's share, from which a group's place in the dimension is found | `group_share` |
| `groups` | A list of interest groups, each a table (below) | none: no groups |
| `group_drivers` | A table from a driver's key to a value over the group dimension: what moves each group, read with `cells()`; shown in its order, as many as given. The UK has eight: since stage S15.2, `stances` ("Where the government stands") and `conditions` ("Rents, bills, pay and farm incomes") join the six before | none |
| `group_driver_labels` | A table from a driver's key to its plain name on screen | the value's label |
| `household` | A table naming the households a group's popup shows (below) | none: no households |
| `[[play.web.areas]]` | One table for each policy area, in order round the board (below) | none |

A **group** has `key`, `label`, `icon`, `row` (the national result row of its approval),
`share` (the row of its share of the electorate, which sets its arc's length within its
family) and `family` (groups of one family stand together on the ring, in the order the
list gives, a gap between families), and optionally `households` (the per-record true/false
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
| `off` | The setting, as typed (pounds for money), at which the policy is not in force: off the board, offered by the Add policy sheet, and repealable when in force. Only for a policy of one lever |
| `line` | One line on what the policy does, on the Add policy sheet |
| `unit` | How the value reads: `years` (an age: "18 years"), `year` (a calendar year: "2030"), `multiple` (of 2024's rates: "as now", "+20%"), `pence` ("52.95p"), `count` (a plain number) |
| `per` | What an amount is for: `"a car"` reads "£2,500 a car" |

An **indicator** has `row` (a national result row, a leading `-` showing it negated),
`icon`, `size` (default 2) and `better` (`"high"` or `"low"`; empty where neither is
clear). Stage S14.1: `better` decides the indicator's colour on the board, which never
changes in play: `"high"` a good thing (green), `"low"` a bad thing (red), none neither
(blue); it also decides the tone of the links that reach the indicator, the tint of its
trend badge, its lines in the month's report and the bars of "In a year". It may carry
`unit` as a policy does. An indicator whose `row` the model lacks is dropped.

A lever that no policy places and that is not hidden gets a policy of its own (the middle
tier, with the generic pictogram) in the area named by its `group`, added at the end of the
board if no area has that name ("Other" for a lever with no group), so a mod's levers are on
the board.

The UK scenario (`models/uk/scenarios/2025.toml`) has ten areas, 55 policies (40 in force
at the start, 15 on the Add policy sheet), 41 indicators (stage S15.2 took nine off the board
and added twelve; `models/uk/STATISTICS.md`), 26 groups in seven families (Beliefs, Work,
Homes and places, Ages, Incomes, Families, Ways of life), four stances and seven places;
its comment block documents the table in place, up to stage S14.1 (the keys new in S15 are
documented here).

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
dimension fill from the next month. Version 5 (stage S14.3) adds the last complete effects
table, which older saves load without. Loading continues exactly and brings the charts
and the board's links back.

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

**Staleness.** The table is computed off the worker (stage S13.1: two levers at a time;
since S14.3 on every core but one, below), so the next month never waits for it. A month, a load, a reload or a new table makes it stale: the
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
and `refused`; saved games keep both (from session file version 4; the current version is
5, which adds the effects table). The client shows the capital at the centre of the board
only (stage S14.1); shows each waiting change's cost in its popup; and reports a bill
refused for want of capital in the month's report.

## How the client is tested

`tools/check_client.py` first reads the scripts' source for the spacing scale (below), then
runs twenty-seven scripts in twenty-nine sessions in Godot without a
display (it needs the bridge copied into `client/bin` by `tools/build_client.py`, after
`cargo build --release --workspace` has compiled it, and the release runner). The first two
compare state hashes with the command-line runner's; the others check what the screen shows
against the model, the runner or published figures. `board_check.gd`, `capital_check.gd`,
`forecast_check.gd`, `people_check.gd`, `policies_check.gd`, `add_search_check.gd`,
`full_term.gd`, `feel_check.gd` and `perf_check.gd` also fail on any script error. Since
stage S15.1 the UK checks read the scenario's areas, groups and families rather than fixed
counts, so a scenario change does not need a check change. The checks reach the
screen through the methods of `main.gd` listed after the table, as a player would.

| Script | Checks |
|---|---|
| `tests/scripted_run.gd` | 60 months through the bridge with lever changes: the same state hash as the runner on every step |
| `tests/ui_run.gd` | The same through the interface's controls (typed values, button presses), with a save, an unchanged reload and a load along the way |
| `tests/reload_run.gd` | A typo in a model file is reported and the game carries on; a real change takes effect the next month |
| `tests/situations_check.gd` | Stage S7.3: in `2025.toml`, no situation after a quiet first month; then, with health spending cut by about a third, a recession: told once, in the month's report, which opens for it, and shown as a pennant on the strip with the month it began |
| `tests/dilemma_check.gd` | Stage S9.1: Valmora with the dock strike mod: a year's run stops at the third month and asks; no month runs until answered; the answer shows as a pennant and raises the government's purchases by a fifth; then the same in French |
| `tests/lag_check.gd` | Stage S10.5: Valmora with the year-on-year mod: the catalogue marks the lag and its twelve states; the board's search links the lag to output as one lagged input; after fourteen months the lag holds the second month's output; its popup's "why it moved" follows it to output's popup |
| `tests/language_check.gd` | Stage S7.4: from the start screen, French is not offered for the UK; Valmora in French has a French Budget and policy popups, and so does a game saved and loaded |
| `tests/start_screen.gd` | Stage S7.1: started without a scenario, the start screen lists the United Kingdom and Valmora and offers the example mod (`mods/dog_licence`, stage S17.1: a mod that adds what the model lacks; the wealth tax that doubled the UK's own is no longer offered) for the UK only; with it ticked, the game starts with the mod's lever on the board, its name in the title bar, and, once the fee is set, a dog licences line in the Budget |
| `tests/migrate_check.gd` | Stage S7.0, run twice on a copy of Valmora: a game saved after four months with the basic rate at 30%; then, with the model's files changed (a new state, the basic rate limited to 25%), the save loads, the rate is at 25%, the player is told, and the next month runs on the new model |
| `tests/second_model.gd` | A model with different names (`models/mini`) gets a working Budget, an automatic board with two policies, two headline figures, and a lever change that reaches the Budget |
| `tests/politics_check.gd` | Stage S5.5, run twice: in `2025.toml`, after a month Parliament shows the 2024 House (411 centre-left seats and the rest), the government's poll rating and the next election in July 2029, and (stage S15.3) as many stance scales and place rows as `[play.web] stances` and `places` give; in `early_election.toml`, the election in the second month is announced, the player has lost office, and advancing no longer moves time |
| `tests/web_walk.gd` | Stage S6.1, through the board: the shortest chain of the model's own connections from the basic rate to the government's poll rating (stage S14.4: from the bridge's `path`), walked back from the rating's popup by following each cause, each step opening that value's popup, and Back |
| `tests/bill_vote.gd` | Stage S5.4: in the UK's hung-parliament test scenario the player's coalition raises the basic rate through its popup and is voted down 324 to 326: the rate keeps its value, the change is recorded as defeated, the player is told, and the chart marks nothing |
| `tests/capital_check.gd` | Stage S12.5: after a month the capital shows (at the centre since S14.1); a basic rate of 22% costs 7.4; two big bills in one month leave the second refused, and the player is told |
| `tests/board_check.gd` | Stage S13.2: every pictogram `[play.web]` names exists in `client/icons` (stage S15.3); the UK board is built from `[play.web]` with exact counts, all read from the scenario (its areas; the policies in force; those not in force kept off it, at least one, each area offering exactly its own; the indicators; the groups in the scenario's order and families); the board holds only centre, group, indicator and policy nodes (no `introduce` node); every lever is on the board or available to introduce. At 1366x768, 1920x1080 and 2560x1440 (the board's size being the window less the top bar and the strip): no two nodes and no labels shown at rest overlap, no node or label is off the board, no node or label but a group's own lies in the group ring or on the rim's area names, and the ring has no faults (an arc running into the next, shorter than its pictogram needs, or out of its family's order; `ring_problems()`); the ring is a circle; every policy and indicator is labelled at rest; the groups' names are at rest all or none. Stage S15.1: the ring grown to thirty groups (the scenario's, its last family filled with copies) at 1366x768 still has no overlap and no fault, its names all at rest or none. A drag and the wheel move no node; every indicator's colour follows its `better`; every node kind opens the right popup (the centre opens Parliament); a basic rate typed in Income tax's popup waits with its cost; pointing at a policy shows links, none passing under the centre; the Budget's lines open popups. Then `models/mini` gets an automatic board |
| `tests/forecast_check.gd` | Stage S13.3: after a month a basic rate of 21% shows, under "In a year", income tax and the budget balance up, and the Commons vote line says it would pass; once the effects table has arrived, Income tax's links are measured and point the way the table has the rate move them; a VAT rise typed after an expensive income tax bill says there is not enough capital |
| `tests/people_check.gd` | Stage S13.4: after three months a group's popup shows the model's approval and as many drivers as the scenario names; Northern Ireland shows a dash (only while it is on the ring; it left in S15.2); stage S15.3: the Socialists' popup lists "Where the government stands" among its drivers and names "The state against the market"; Sentencing set to Tougher shows, in "In a year", the Conservatives' approval up and the Liberals' down, and in the effects table the order stance up; eight households are shown for a group, each in it, and a household's account adds up to its net income; a basic rate of 21% lowers high incomes' approval by more than low incomes' in "In a year"; pointing at Income tax links the budget balance and unemployment, both up (green and red by what is good for each). Valmora, which has no groups, gets a board with an empty middle |
| `tests/policies_check.gd` | Stage S13.5: each area's list on the Add policy sheet (stage S15.1) holds exactly its policies not in force; the new indicators have figures; the electric car grant introduced at £2,500 shows the electric share up and the balance down, puts a ghost on the board and spends capital, is in force after the month and in the report, and leaves the board when repealed; a level policy offers its named levels and stores the level chosen; the drinking age reads in years and raising it lowers the young's approval in a year; a higher fuel duty shows motorists against and receipts up, and pointing at it links motorists; an unaffordable introduction is refused, its ghost goes and the report says why; an estimated group's popup says so and shows no households |
| `tests/add_search_check.gd` | Stage S15.1: after a month, no "New policy" node on the board; A opens the Add policy sheet, and every area lists exactly its policies not in force (an area with none greyed); choosing one closes the sheet and opens its popup at its first step, ready to put to the Commons; put, it waits on the board as a ghost, and after the month it is in force (or the report says why not). "/" focuses search; "strong growth" finds the situation and lights the Growth node; "fuel" finds Fuel duty first and Enter opens it; Esc clears; a situation's pennant lights its node and opens it with "Set off by"; a situation in force flags its node |
| `tests/full_term.gd` | Stage S13.6: all sixty months of the UK's term played through `main.gd`'s methods with nineteen decisions (taxes, spending, three introductions, level policies, a repeal), every question answered, each kind of popup and both sheets opened; no month fails; each bill's fate is what the report said, a third bill in one month is refused for capital, and capital adds up and never goes below zero; the report after every month (open for a month with bills, else its line under the date); the election comes in July 2029 and its result is announced; a game saved in month 24 and loaded gives the same state hashes to month 36 |
| `tests/feel_check.gd` | Stage S13.6, at 1366x768: at step 0 every figure shows the awaiting state, and every popup kind and both sheets open with no "nan"; no change too small to show reads as a signed nought; the guide is wanted on a first game from the start screen, never with `--scenario` or headless, and its five steps point at real things; Space and Enter run months; a bill refused for want of capital and one passed appear in the report with the figures that moved most, and the refusal is not also in a notice. Stage S14.1: the report floats (the board keeps its size and the centre its place), the date opens it again, it does not cover the centre, Esc closes it, and the next month asked for closes it at once and runs; the links of a node held under the pointer while the table arrives change at most once; B, P, K (the key, with at least four of the board's own drawings) and Esc do their jobs, and Space does nothing in a focused field. Stage S14.4: a game saved and loaded has measured links on the first hover, from the table in its save, and asks for no table. A game from the start screen opens with its first month played; the sound helper asks for its sounds and makes no player headless |
| `tests/contrast_check.gd` | Stage S17.1, without a scenario: every pair of ink and ground in `contrast.gd`'s `pairs` (the words the scripts draw themselves, the inks text is set in on every ground, the theme's states under the pointer and pressed, and the marks that carry meaning) reaches its WCAG 2.1 ratio, 4.5 to 1 for text and 3 to 1 for text of 18 px or more and for marks; then the start screen, the top bar (at the start, after three months, with the capital short, while searching), the strip (with a problem announced), the search's matches and the guide are walked as they stand and every piece of text measured against what is under it |
| `tests/folds_check.gd` | Stage S17.1: at 1366x768 and 1920x1080, a policy (at rest, with a change waiting and its year ahead, of levels, repealable, being introduced with and without a setting), five statistics on the board and one off it with each fold open, four groups of voters with each fold open and a household's account, a situation, and The Budget, Parliament with each fold, Add policy, the key, help and the month's report: each card inside the window and under the top bar, nothing in it poking out of its sides, no label or button narrower than its words, no text under 12 px, and every piece of text at its contrast ratio against the ground it stands on. `--shots=DIR` with a display also photographs each card and the whole screen |
| `tests/focus_check.gd` | Stage S17.1: with Next month holding the keyboard, a policy, a statistic, a group of voters, a situation, The Budget, Parliament, Add policy, the key, help and a question are opened in turn and Tab pressed once for each control: the keyboard goes in, reaches each control once in the order the card is built (never up and to the left at once), each shows a ring (2 px, 3 to 1 against the ground round it), the press after the last returns to the first and Shift+Tab goes back; Esc closes the card and Next month has the keyboard again; a popup opened from a Budget line closes first, back to that line |
| `tests/bar_check.gd` | Stage S17.1: three months in, at 2560 wide the top bar has every figure, the search field and every word; narrowed ten pixels at a time to 1200 it never needs more than the window, gives way in the stated order and never out of it, keeps every headline figure at 1920 and approval and capital throughout, also with the capital short; at 1366 "/" opens the search's button and Esc shuts it; widened, all comes back |
| `tests/perf_check.gd` | Stage S14.1, the speed budget, at 1920x1080 on the UK after a month; it prints every figure and fails if one is over (stage S17: it first times the machine, on the engine's own twelve-month look ahead and a fixed loop of script, and where the machine takes k times the reference's time the budgets the processor bounds, every one but a popup's opening and closing and the idle count, are k times as long; a forecast over budget is measured once more): a click to a popup fully open 120 ms and its close 80 ms (medians of five over two policies, two indicators and a group, measured again once if over); board redraws in an idle second with a popup open 0; "Next month" to the date and board showing it 150 ms (median of three, while the last table is measured); twelve months 1 s; pointing at a policy straight after to measured links 16 ms (one frame); and (stage S14.4) a basic rate typed to "In a year" filled 600 ms (median of three); and (stage S15.1) a key typed into search, its matches, list and the board's dimming, 4 ms on average over "unemployment" typed and deleted a letter at a time, with no engine call |
| `tests/budget_dump.gd` | The UK's Budget after one month, read as text and parsed back: every line within 1% of the 2024 public finances in `models/uk/data/annual.csv` (totals, shown to three figures, within 0.6%), and no input marked `player = false` among a policy's controls. Then every breakdown, as shown in the popups of the figures they break down, after that month and after a second with the basic rate one point higher: every group shown with its label; all households' net income equal to the runner's to the pound; the rise taking from the fifth decile up, from each of the top three at least £100 a year more than from the poorest, and from every region but Scotland, which sets its own rates |

**Spacing, contrast and type, held by checks (stage S17.1).** Every margin, and every gap
between one thing and the next, is nought or on one scale, 4, 8, 12, 16, 24, 32 pixels,
named once (`Palette.SPACE`); a number off it has "off the scale:" and the reason on its
line (the leading closed up between a caption and its figure on the top bar; the thickness
of a slider's track and of a scroll bar, which are marks, not gaps). `check_client.py` reads
this from the source (container separations and margins, style boxes' content margins, the
margins handed to the palette's box makers), so it holds for screens no check opens; sizes
of things and the coordinates of what the scripts draw themselves are not gaps and are not
held to it. Text is set in inks that reach 4.5 to 1 on every ground it stands on (card
stock, the top bar's band, a field, the paper to its darkest corner): `MUTED`, `GOOD`, `BAD`
and `PENDING` are each a shade deeper than before, and `BAD` is no longer brick itself,
which is kept with sage and ochre for fills. A mark that carries meaning reaches 3 to 1 or
is keyed in ink: what is filled of a group's approval gauge (mustard was 1.5 to 1 against
its track), the ring round the node whose popup is open, a guide's target; an unmeasured
link is ink at 60%; three blocs' colours (gold, yellow, grey) are deeper; the search's
placeholder is ink at 70%. No text is under 12 pixels. A button is 37 pixels tall (8 above
and below a line of 15-pixel type). A link has nothing at its sides, so its words start and
end where the plain text above and below them does, and a popup's Back and Close stand on
its content's edges; a fold's heading likewise, its tint under the pointer reaching 4
pixels past its words. A chart gives its marks the room the widest needs, marks both ends
of its range, leaves off a mark that reads as the one below it, gives a rate's marks one
number of places, and draws a single point 4 pixels in radius. No bar is drawn beside a
change that reads "no change" or "0.00". A column of money is in whole pounds when any of
its rows is. A nought has no sign, and a negative percentage a true minus sign. An area
too narrow for its name on the rim is named by what comes before its "and" (ENVIRONMENT),
and one too narrow for that keeps only its arc. A popup holds one content: opening one
empties the card of whatever a closing cut short had left in it.

**What `main.gd` offers the checks.** Actions: `open_node(key)` (a board key, or the key
of a policy not in force), `open_indicator(name, row, origin)`, `open_add_policy(key)`
(stage S15.1: the Add policy sheet, at a policy not in force or, with "", the first area with
something to add), `search_for(words)` (focuses the search field and types; returns the
matches), `open_situation(name)`, `open_overlay("budget" | "parliament")`, `close_overlay()`, `close_popup()`,
`type_lever(lever, value)` (into the policy's popup, opened if need be, as a person types),
`hover(key)`, `introduce_policy(key, value)` (opens the popup of a policy not in force, picks
the setting and presses **Put to the Commons**; returns the bill's text, or "" if none was
put), `repeal_policy(key)`, `open_introduce(area)` (since S15.1 the Add policy sheet at that
area), `advance(months)`, `answer_dilemma(name,
answer)`, `ask_dilemma()`, `menu_action(action)`, `set_ui_scale(choice)`,
`set_volume(volume)`, `show_guide(remember)`, `show_key()`, `show_per_year(on)`,
`save_game()`, `load_game()`, `start(path)` and `start_from_screen(path, mods, resume)`.
Readers: `popup_kind()`, `policy_card()`, `group_card()`, `indicator_card()`,
`add_sheet_open()`, `add_list` (the sheet's content: `area`, `keys`, `rows`),
`situation_node(name)`, `search` (the field: `found`, `chosen`, `text`), `strip` (its
`flag_pressed` signal, as a click on a pennant), `current_trace()`, `overlay_open()`, `board_levers()`,
`available_policies(area)`, `latest_value(row)`, `previous_value(row)`, `flag_text(key)`,
`capital_text()`, `title_text()`, `notice_text()`, `notice_visible()`, `dilemma_title()`,
`unanswered_dilemmas()`, `can_advance()`, `advance_queued()`, `awaiting()`,
`guide_steps()`, `guide_seen()`, `should_guide(from_start_screen, headless, seen)` and
`situation_onset(row)`; the fields `effects_running` and `effects_requests` (stage S14.4:
the table asked for, and how many times); the month's report's `lines_shown`, `visible`,
`reopen()` and `dismiss()`; and the cards' own fields (for the policy card, `year_shown`,
`year_groups`, `year_all_groups`, `measuring` and `draft`; for the group card, `records`,
`drivers_shown`, `approval_text` and `stance_text`; for a situation's card, its "Set off by"
words; Parliament's `stance_rows` and place rows). The board's `nodes`, `order`, `areas`,
`available`, `available_in(area)`, `policy_of(lever)`, `policy_node(key)`, `effects`,
`link_sets`, `links_for(key)`, `linked(key)`, `keys_of(kind)`, `layout()`, `overlaps()`
and (stage S15.1) `searching`, `matches`, `lit` and `node_flags` are read directly, and board_check and feel_check also read a few of its private fields (the group
ring, the links shown).

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
| `--node=KEY` | Open a node's popup: `policy:income_tax`, `indicator:gdp`, `group:pensioner`, `centre` |
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
| `--key=1` | Show the key |
| `--add=1`, `--add=KEY` or `--add=area:NAME` | Stage S15.1: open the Add policy sheet, at a policy not in force or at an area (`+` for a space) |
| `--search=WORDS` | Type into search (`+` for a space) |
| `--situation=NAME` | Open a situation, lit on its node |
| `--guide=N` | Show the guide's Nth step |
