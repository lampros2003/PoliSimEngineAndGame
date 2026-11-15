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
| S13.2 | Under way |
| S13.3 | Not started |
| S13.4 | Not started |
| S13.5 | Not started |
| S13.6 | Not started |

Not in this stage: ministers and a cabinet, media, constituency maps, release work.
