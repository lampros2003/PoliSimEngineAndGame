# Stage S13: the web is the game

## Context

The S12 client was rejected, rightly. It is a dashboard with pages; the policy web is a
side page of boxes; the right column (chart, Why, Connections) does nothing useful; the
only policies are budget lines in odd categories; there are no approvals, no interest
groups, no household views; the NHS waiting list sits beside GDP; the map is poor; and the
look is generic. The owner wants the Democracy 3 / Orbi Universo kind of game: **one
full-screen cause-and-effect graph that is the main way to play**, nodes sized by
importance, everything opened by clicking a node, real-life policies (an EV incentive, a
drinking age), approvals by interest group, households you can look at, and a crafted
look. Written 2026-11-14, after S12, at the owner's request; the decisions below are made
under his brief.

This is an original game in that genre: its own layout, art and rules. Nothing is copied
from another game's screen.

What research and the code established (so the plan stands on facts):

- Genre patterns worth keeping: links shown only for the node under the pointer, signed
  and with strength; a policy opens to a slider with cost, capital and effects; groups
  show size and approval; a board that starts small and grows. Known faults to avoid:
  clutter, tiny text, no UI scale.
- Crafted versus dashboard: one visual metaphor, shape for node type, size for importance,
  a limited palette with one accent, material (no white cards), a display typeface, motion
  and sound on every interaction, popups that grow from their node. No Godot UI framework
  is worth adopting; built-in `Theme`, `Tween`, `_draw` and `canvas_item` shaders do it.
- The model has no approval value, only vote choice by 600 voter types
  (region x age band x income fifth x in work); `sum_by` can aggregate them into groups,
  and national scalars get a history for charts. Households carry adults' ages, earnings,
  pensions, self-employment, children and region, but no tenure, car or sector.
- A game can be forked in memory (`Session::save` then `Session::load`, about 50 ms, a UK
  month 15 ms), so **effects can be measured by running the model ahead**, not declared.
- A lever can already act beyond money: service levels, NHS treatments, emissions, the
  issues voters weigh, `government_standing` by voter type (as dilemmas do), prices,
  trade; curves can read levers; mods patch formulas with `{base}`.
- No indicator exists for crime, health outcomes, education outcomes, housing, transport
  or immigration.

## Decisions

| Question | Decision |
|---|---|
| Main screen | One screen: **the web**, full window, pan and zoom. A slim top bar (country and month, approval, political capital, budget balance, debt, growth, unemployment, month controls, menu). No pages, no right column, no Chart/Why buttons, no Connections tab, no map |
| Layout | Authored and stable, not force-directed. Rings read inward, cause to people: **policies** on the outer ring in arcs by area, **indicators** on the middle ring in their area's sector, **interest groups** round the centre, the government's **approval and capital** at the centre. Area names set along the rim. Elliptical so it fills a wide screen |
| Nodes | Shape says type (policy disc, indicator ring, group shield, situation flag); **size says importance** (three tiers from the scenario, a pulse when it moved); a gauge arc shows a policy's setting and a group's approval. Icon-only at rest, labels for the largest nodes and on hover or zoom |
| Links | Only for the node under the pointer or selected; everything else dims. A policy's links are its **measured effects after a year** (top effects only): arrow and colour for direction, width and dash speed for strength. An indicator shows the policies that move it most and the groups it moves |
| Clicking | Every node, top-bar figure and budget line opens a **popup that grows from it**: a policy gets its control(s), cost in capital, the Commons vote it would get, what it would do in a year (budget, indicators, groups), and its history; an indicator gets its chart, why it moved (the existing trace, followable), its breakdowns (by income tenth, region, household type) and what moves it; a group gets approval, size, what is driving it, and its households |
| Other views | Overlays opened from the top bar, not pages: **The Budget** (a ledger; every line clickable) and **Parliament** (seats, polls, election, issues), also reached from the centre node |
| Policy areas | Economy, Tax, Welfare, Health, Education, Law and order, Transport, Environment and energy, Housing, Foreign and trade. Many-lever policies become one node with several controls (Income tax, National Insurance, Universal Credit, Child Benefit). Scotland's devolved income tax rates stop being the player's |
| A growing board | New policies start **not in force** and off the board; each area has an "introduce a policy" node. Introducing, changing and cancelling cost political capital (the S12.4 rule, kept) |
| Approval | A group's approval is the share of its likely voters who back the governing blocs, from the model's own choice shares, so it moves with incomes, jobs, prices, services, time in office and reactions to policies. National scalars per group, so each has a chart |
| Interest groups | First from what the model knows exactly: the young, mid-life, pensioners; low, middle and high income; in work, out of work; parents, lone parents, the self-employed; Scotland, Wales, Northern Ireland, London, the North, the Midlands, the South. Then, with the policies that need them, groups by published shares (motorists, home owners, renters, drinkers, public-sector workers), documented as estimates |
| Household views | In a group's popup: a row of sample households from the 20,000 records, as pictograms (adults, children), each opening to its income statement: earnings, taxes, benefits, net income, change, likely vote |
| Real policies | About twenty to start, in real units where natural (a drinking age in years, an EV grant in pounds per car, a minimum wage in pounds an hour, fuel and alcohol duty, a visa cap) and levels where not (planning rules, sentencing, rent controls). Each has its money through the accounts, its effects through curves, and group reactions. Six new indicators: crime, public health, school attainment, homes built, net migration, EV share of new cars. Effects are documented judgements around published 2024 bases; **every policy is neutral at its default**, so the base month and the 2005-2024 hindcast do not move |
| Look | **Pictorial statistics**: the mid-century public-information print tradition (Isotype charts): warm paper ground with grain, ink navy, brick red, ochre and sage as flat colours, one accent for "you can act here", silhouette pictograms, people drawn as rows of figures. Display face Jost (Futura lineage), text and figures IBM Plex Sans with tabular numbers (both OFL). Icons from game-icons.net (CC BY 3.0, credited in Help and a credits file) |
| Feel | Hover lift, popups that grow from their node and close faster than they open, links that draw in and flow, numbers that count, nodes that pulse after a month; CC0 interface sounds (Kenney) with a mute switch; a UI scale setting; readable from 1366x768 to 2560x1440 |
| Presentation data | The board's areas, policy nodes, indicator tiers and "better high or low" live in the scenario's `[play.web]`, hand-written, so no model hash changes for layout; another model without it gets an automatic board |

## Milestones

Each is checked as under Verification before the next begins, so the branch always holds a
working game, most valuable part first.

| # | Stage | Files | Done when |
|---|---|---|---|
| S13.1 | **Engine and bridge: looking ahead.** Fork a session and run it ahead with and without changes; an effects table (each policy nudged one step, a year on); the Commons vote a change would get; sample records of an entity | `crates/core/src/session.rs`, `sim.rs`, `crates/godot/src/lib.rs`, `crates/core/tests/` | Rust tests: a forecast equals actually playing those months, byte for byte; forks never disturb the game; fmt, clippy, tests clean |
| S13.2 | **Client: the web as the screen**, popups, overlays, the new look and motion; pages, map, Connections and the right column removed. Runs alongside S13.1 against the contract below | `client/scripts/*` (new `web.gd`, `popup_*.gd`; `palette.gd` rewritten; `map_panel.gd`, `web_panel.gd`, `policy_web.gd` deleted), `client/fonts`, `client/icons`, `client/tests/*`, `tools/check_client.py`, `models/uk/scenarios/2025.toml` (`[play.web]`) | Every scripted check passes (rewritten where it reached into a removed panel, still proving the same thing); screenshots at three sizes reviewed |
| S13.3 | **Join them:** measured links, the year-ahead table and the vote in the policy popup | client | A scripted check: raising the basic rate shows revenue up and the top fifth's approval down; hover links match the effects table |
| S13.4 | **People:** group approvals in the UK model, groups at the centre, the group popup with drivers and households | `tools/uk/voters.py`, `models/uk/politics.toml`, recordings, `oracle/tests`, client | Oracle and engine agree (recordings regenerated, random scenarios, hindcast check); group approvals weighted by size reproduce the national poll rating |
| S13.5 | **Real policies and indicators**, introduce and cancel, estimated groups | `models/uk` (new hand-written policy file and `POLICIES.md` with every source and judgement), `tools/uk`, scenario, client | Defaults leave the base month and hindcast unchanged; each policy has a test that it moves what it claims; both implementations agree |
| S13.6 | **Finish:** sound, UI scale, first-minutes guidance, `docs/GUIDE.md`, spec 05, the wiki page and the build skill | docs, client | A full five-year scripted game through the new screen; final screenshot review |
| S13.7 | **Balance**, from `docs/S13-BALANCE.md` | `tools/uk`, `models/uk`, `oracle/tests`, `crates/cli`, client tests | The decisions below are in the model; the playtest's strategies are run again and reported beside the first results; every check passes |
| S13.8 | **The public finances matter**: lenders and voters react to borrowing | `tools/uk`, `models/uk`, `oracle/tests`, the 2025 scenario | The decisions below are in the model; the strategies are run a third time; borrowing to spend no longer wins the most seats; every check passes |

### S13.7: what the playtest changes

The playtest found the election won by doing nothing (344 seats), one strategy that beats
the rest (raise taxes early, please voters late), political capital that prices the biggest
decisions lowest, one policy far too strong and six too weak to notice.

| Question | Decision |
|---|---|
| How long voters remember their incomes | Half the income term compares real income with a year's memory, as now, and half with its level at the last election, as jobs, prices and services already are. A tax rise early in the term still costs something on polling day, and a late giveaway still helps, but neither is free |
| What doing nothing gives | It should leave the majority in doubt, not safe. After the other changes, if doing nothing still wins well clear of 326 seats, the 2025 scenario sets the wear of office higher through its own parameters, documented, until it lands near the line |
| What bills cost | The big spending lines weigh 3 and the main tax rates 2, so a quarter off the NHS costs more than a penny on a duty. The dearest introductions weigh 0.6 |
| How capital is earned | Centred on the ratings the model produces (20% to 40%), 1.5 a month at least, and from the player's own bloc, so a coalition does not inflate it. The centre of the board shows that bloc's rating |
| Policies out of line | Fuel duty's direct reaction is cut by three quarters. The soft drinks levy, the bus fare cap, the prescription charge, the Winter Fuel Payment, cannabis law and the drinking age are made large enough to notice. Liberal planning stops being a net loss |
| Pacing | The questions that repeat get a cool-down; two chance questions are added for 2028; new situations for crime, healthy life, homes built and migration |
| Left for later | The fall in pensioner poverty in one month (identical pensions in the synthetic households cross the poverty line together): it needs the households rebuilt, which moves the base month. A repeal costing half an introduction: an engine rule |
| The runner and the game | `polisim play` charges a month's bills last made first; the game charges them in the order made. The runner follows the game |

### S13.8: the public finances matter

After S13.7 the playtest's remaining fault is that borrowing is free: the crowd-pleaser runs
the largest deficit (£235bn a year) and wins the most seats, and austerity, which halves the
deficit, loses the majority. Nothing in the model makes voters or lenders mind.

| Question | Decision |
|---|---|
| Lenders | The yield on new gilts carries a premium when borrowing as a share of output runs above its level at the start of the game, and a discount below it. It reaches debt interest, as the yield already does, and what households and firms pay to borrow where the model has that path |
| Voters | The government's standing carries a term for the public finances: borrowing against its level at the last election, weighed like prices and jobs, heavier among pensioners, home owners and high incomes. Group popups show it as a driver of its own |
| A crisis | A question that opens when borrowing stays far above its starting level: lenders refuse the government's gilts. Its answers are an emergency budget, holding course at a much higher yield, or asking the Bank to buy, each with its price. A situation for falling borrowing ("lenders' confidence") is the reward at the other end |
| On the board | The gilt yield is an indicator in Economy, lower is better, linked from the policies that move borrowing |
| What must not move | The base month, the fitted intercepts and the 2005-2024 hindcast: every term is nil at the starting level, or nil by default and set by the 2025 scenario, as the wear of office is |
| What it should give | Spending paid for by borrowing gains at first and loses by the election; austerity ends near the majority line, not seventy seats under; a government that pays for what it spends does best; wrecking still loses |

### Bridge contract for S13.1 and S13.2 (fixed now so both can proceed)

- `request_forecast(changes: Dictionary, months: int, tag: String) -> bool`; event
  `{type: "forecast", tag, months, rows: {row: [as_is, changed]}, cells: {name: {as_is, changed}}, error}`.
  "As is" includes the changes already waiting.
- `request_effects(levers: PackedStringArray, months: int) -> bool`; one event per lever
  `{type: "effects", lever, step, rows, cells}`, computed off the game's worker so "Next
  month" never waits; a new month discards what is stale.
- `vote_preview(lever: String, value: Variant) -> Dictionary` `{bill, votes_for, seats, passes, cost, affordable}`.
- `request_records(entity, where_row, count, columns, tag) -> bool`; event
  `{type: "records", tag, records: [{id, weight, ...}]}`, the same records for the same request.
- The client uses `has_method` and degrades quietly until S13.3.

### Reused, not rewritten

`chart.gd` (history chart), `trace_panel.gd` (`show_explanation`, followable), the lever
input logic in `lever_panel.gd` (`_scale`, `_money_unit`, `type_value`), `format.gd`, the
reach search in `policy_web.gd` (for the automatic board), `budget_panel.gd`'s line
building, `Session::save/load`, `Simulation::column/evaluate`, `bill_cost`, the dilemma
dialog, saves, mods, languages.

## Verification

After every milestone, from the repository root (an open game window locks the bridge DLL:
close it first):

- `cargo fmt --all --check`; `cargo clippy --workspace --all-targets --release -- -D warnings`; `cargo test --release --workspace`
- `cd oracle; python -m unittest discover -s tests`; `python tools/uk/hindcast.py --check`
- `python tools/diff_engine.py --count 150`, and with `--model models/uk --count 10 --max-steps 4`, `models/cohort --count 40`, `models/raking --count 40`
- `python tools/build_client.py --godot <console exe>`; `python tools/check_client.py --godot <console exe>`
- Screenshots of the board, each popup kind and each overlay at 1366x768, 1920x1080 and
  2560x1440, looked at before a milestone is accepted.

## Status

| # | Status |
|---|---|
| S13.1 | Done. `Session::fork`, `forecast`, `vote_preview` and `records`, and `Fork::effects` (`crates/core/src/session.rs`); the vote moved into `Chamber::ballot` and `preview` (`sim.rs`), unchanged in what it decides; the bridge's `request_forecast`, `request_effects`, `vote_preview` and `request_records` (spec 05, "Looking ahead"). A fork is a direct copy of the simulation (about 8 ms for the UK), applies changes without a vote or a charge of capital, and never answers a dilemma. A twelve-month UK forecast takes 0.3 s; the effects table for every lever about 8 s on its own thread, two levers at a time, dropped when the game moves on. Ten tests (`crates/core/tests/forecast.rs`): a forecast equals playing the months; nothing disturbs the game; the preview agrees with the Commons for a passed, a defeated and a refused bill |
| S13.2 | Done. `client/scripts/web.gd` is the board: elliptical rings from the scenario's `[play.web]` (the UK: ten areas, 24 policies holding 53 levers, 24 indicators; an automatic board without the table), three sizes, gauges, pulses, links only for the node under the pointer; `popup.gd` and `lever_panel.gd` (the policy popup), `indicator_card.gd`, `sheet.gd` (The Budget, Parliament, dilemmas). Pages, the map, Connections, the right column and the Chart and Why buttons are gone. The look is pictorial statistics: paper ground, flat inks, Jost and IBM Plex Sans (OFL), 62 pictograms from game-icons.net (CC BY 3.0, `client/icons/CREDITS.md`). `main.gd` has methods for the scripted checks (`open_node`, `open_overlay`, `type_lever`, `hover`...), which were rewritten to play through the board; `tests/board_check.gd` is new |
| S13.3 | Done. Hover links are the effects table's strongest eight, signed as measured; the policy popup shows "In a year" from a forecast and the vote the Commons would give, with the capital it needs (`tests/forecast_check.gd`: a 21% basic rate shows income tax up by five billion pounds and household income down) |
| S13.4 | Done. On the board the eighteen groups stand round the centre as shields in five families, sized by their share of the electorate, each with its approval; a policy's links reach the groups it moves most, and a group's the policies that matter most to it. A group's popup (`client/scripts/group_card.gd`) shows its approval against the country's, its share as a hundred figures, what is moving it, and eight of its households, each opening to its account for the year; Parliament lists the country by group. Every node now has a label where one fits, and the policy popup puts its controls first with "In a year" beside them (`tests/people_check.gd`). The model: A `group` dimension of 18 (`tools/uk/voters.py`): the young, mid-life, pensioners; low, middle and high incomes; in work, out of work; parents, lone parents, the self-employed (their shares summed from the households each month); Scotland, Wales, Northern Ireland, London, the North, the Midlands, the South. For each, the rows `approval_<group>` (the governing blocs' share of the group's likely voters) and `share_<group>`, and by group `group_approval`, `group_share` and five drivers that add up to the group's mean performance utility (`models/uk/politics/README.md`, "Groups"). Per household: `household_in_<group>`, `household_support`, and the year's earnings, pensions, income tax, National Insurance and benefits (`tools/uk/make_rules.py`). Scotland's eleven devolved income tax levers are no longer the player's. In January 2025 the young back the government at 49%, pensioners at 21%, the national rating being 33.8%; weighted by likely voters the groups of each partition reproduce it to twelve places. A 25% basic rate takes a point off high incomes' approval in a year and a tenth of that off low incomes'. Every earlier value and every recorded hash is unchanged; the month costs about 17 ms, from 14.5. `capital.toml` now has its template, so `tools/uk/calibrate.py` runs to the end again |
| S13.5 | Done. On the board every new policy, indicator and group has its place, name and pictogram; a level policy is chosen by name, an age reads in years, a duty as a change on today's, money in its real unit. A policy standing at its `off` setting is not in force and not on the board: each area with such policies has a "New policy" node listing them with what the smallest step in would cost; a bill to introduce one shows as a ghost until the Commons has voted, and a policy in force with an `off` setting can be repealed from its popup (`client/scripts/introduce_list.gd`, `tests/policies_check.gd`; `[play.web]` gains `levels`, `off`, `line`, `unit`, `per` and `estimate`). The UK starts with 38 policies in force and five to introduce. The model: Nineteen policies in `tools/uk/template/policies.toml` (copied to `models/uk/policies.toml`), each neutral at its 2024 setting: the legal age to buy alcohol, sentencing, cannabis law; alcohol and tobacco duty, the soft drinks levy, the prescription charge; fuel duty, an electric car grant, the bus fare cap; a home insulation programme, the year of the ban on new petrol and diesel cars; the tuition fee cap, free school meals; planning rules, a social housing programme, rent controls; the Winter Fuel Payment; the skilled worker visa threshold. Six indicators from their published 2024 levels: crime (9.2m incidents), healthy life expectancy (60.8 years), school attainment (45.9%), homes built (221,070), net migration, and the electric share of new cars (19.1%). Five estimated groups (motorists, home owners, renters, drinkers, smokers) from published shares by voter type. Money goes through the existing flows; effects through single terms that are zero or one at the defaults; reactions through `government_standing` (`models/uk/POLICIES.md` gives every source and says which sizes are judgements). All 371 earlier result columns are identical over 24 months and the hindcast is unchanged; the recordings are re-recorded and the engine reproduces them (`oracle/tests/test_policies.py`, 15 tests). Dropped: a minimum wage (the households have no hours) |
| S13.6 | Under way. Done: interface sounds (Kenney, CC0) with a switch and volume; the month's report of bills, biggest movers and situations; a five-step guide on a first game; keys (Space, Esc, B, P, H); a new game opens with its first month played, so no figure is ever blank; hover links hold steady while measurements arrive (`tests/feel_check.gd`). `docs/GUIDE.md` and `docs/spec/05-game-client.md` are rewritten for the board (the spec gives the `[play.web]` table, the popups and sheets, the checks and the methods they call). `tests/full_term.gd` plays all sixty months through the board with nineteen decisions, thirteen questions, a refusal, a repeal and a save and load in the middle, and is in `tools/check_client.py`. The same playtest, run eight ways, is `docs/S13-BALANCE.md` |
| S13.7 | Done. The model: half of a household's `income_change` now compares real income with its level at the last election (`income_at_election`, `income_election_share` 0.5; the fitted income effect kept, `models/uk/politics/README.md`, "Memory of income"); `capital_weight` 3 on the spending lines of 5% or more of what the player sets (health, education, social care, police and courts, the benefits bill, public investment) and 2 on the basic rate, VAT, the main and employer National Insurance rates and corporation tax, 0.6 on cannabis law and rent controls (the generators); capital earned at 1.5 a month and up to 5 more on `(own_support - 0.20) / 0.20`, the player's own bloc's rating (`own_support`, "Your party's poll rating", named `own` in the 2025 scenario's `[play.politics]`, and shown by the board's centre and the top bar's Approval); fuel duty's reaction a quarter of what it was, the soft drinks levy, prescription charge, bus fare cap, Winter Fuel Payment, cannabis law and a drinking age of 16 two to four times stronger (0.2 to 0.5 points nationally, 0.6 to 2.1 in their groups), liberal planning a small gain (`models/uk/POLICIES.md`); the NHS winter crisis and full prisons again only after two years; fuel protests and small boats from 2028; six situations for crime, healthy life, homes built and migration; and the 2025 scenario's `[params] vote_wear_effect = -0.025`, a new model parameter (nil by default) for each year in office beyond six months, so the base month and intercepts do not move. Every economic value of the base month is unchanged (only political capital differs), the hindcast check passes, and the four UK recordings are re-recorded. Doing nothing now keeps 330 seats (344 before), 323 with the second answers; the crowd-pleaser wins most (382) and "tax early, please late" no longer dominates (361), but deficits are now the free lunch (`docs/S13-BALANCE.md`, "After S13.7"). `polisim play` takes a month's bills in the order the game does (a lever changed twice moves to the end; `crates/cli/src/play.rs`, with a test). Rust tests whose figures moved (`bills.rs`, `forecast.rs`, `uk_dilemmas.rs`), `oracle/tests/test_groups.py` and `test_situations.py`, and `client/tests/capital_check.gd` were updated to the new costs and names |
| S13.8 | Done. `models/uk/finances.toml` (new, from `tools/uk/template/finances.toml`): borrowing as a share of GDP smoothed over a year (`borrowing_smoothed`), its level in the first month (`borrowing_at_start`), and a lenders' premium on new gilts of `lender_premium_effect` points per point above it, capped at +2 and -0.5 (`gilt_premium`), in `gilt_yield_now`, which the average rate on the debt now follows (a hook in model.toml, so the hindcast model is unchanged); the model has no other interest-rate path to households or firms, so it stops at debt interest. Voters (`tools/uk/voters.py`): `voter_finances`, a curve of smoothed borrowing against the last election (mild to a point of GDP, steep beyond), weighted towards pensioners, home owners and the richest fifth, a sixth driver of approval ("The public finances" in `[play.web]`), and 0.01 of standing while "Lenders' confidence" holds. A dilemma, "Lenders refuse the gilts", at 1.2 points above the start (emergency budget, hold course, the Bank buys); "Debt above a year's output" re-based as "Debt rising fast" (seven points above the start); the gilt yield on the board in Economy. Both reactions are nil in the model and set by the 2025 scenario's `[params]` (`lender_premium_effect` 0.75, `vote_finances_effect` 1); the base month is unchanged in every value and the hindcast check passes. Doing nothing keeps 325 seats; the crowd-pleaser leads for two years, meets the crisis in August 2027 and ends with 312; austerity 314 (274 before); "tax early, please late" 364 and the reformer 336 win the most; the wrecker loses office (`docs/S13-BALANCE.md`, "After S13.8"). New tests in `oracle/tests/test_finances.py`; `crates/core/tests/uk_dilemmas.rs` gives the crisis's answers |

Not in this stage: ministers and a cabinet, media, constituency maps, release work.
