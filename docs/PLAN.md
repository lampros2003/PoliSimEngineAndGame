# Plan from here

Written 2026-11-14, after stage S1. This is the working plan: what gets built next, in
what order, how each piece is checked, and what is needed from the project owner and
when. The long-range roadmap and the evidence behind it are in
`reports/PoliSim engine architecture pathways.md`; the current state of each exit test is
in `README.md`. Update the status column here as milestones close.

## Where we are

| Stage | State |
|---|---|
| S0 Specification, oracle, data gate | Done except the data-licence check, which is recorded as not passed |
| S1 Rust core | Done except the Python module, which was deferred |
| S2 Playable shell | Built and tested in CI (2026-11-14). The two exit tests that need the owner at a Windows machine are open |
| S3 to S7 | Outlined below; S3 is planned in `docs/S3-PLAN.md` (done), S4 in `docs/S4-PLAN.md` (done), S5 in `docs/S5-PLAN.md` (done), S6 in `docs/S6-PLAN.md` (done), S7 in `docs/S7-PLAN.md` (its building milestones done; the business decisions are the owner's) |
| S8 What government does | Added after S7: spending by function, what services deliver, emissions, the issues voters weigh (`docs/S8-PLAN.md`, done but for the NHS waiting list, whose source is not reachable from this environment) |
| S9 Dilemmas, prices, history | Chosen by the owner on the decision page (2026-11-14): the NHS waiting list, dilemmas, taxes that reach prices, and the voters' reactions fitted to past elections (`docs/S9-PLAN.md`, done; the fit to past elections is weak evidence and only moves the judgements a little). Open for the play test: a seed of its own for each new game, and the size of the dilemmas' political costs |
| S10 The engine: speed, reliability, power | At the owner's request (2026-11-14) (`docs/S10-PLAN.md`, done): a profile by formula; records, cells, sums and independent formulas on several threads (the UK's month 29 to 20 ms, every hash unchanged); thread-count, fuzzing and failure-order tests, and a game that survives a panic in its simulation thread; `div`, `mod`, `largest`, `smallest` and `sum_by` in the formula language; loading three times faster; lags (`[lag.x]`); `ln`, `sqrt`, `pow` and `quantile`; national parts of record formulas computed once |
| S11 Curves, who loses out, speed | Chosen by the owner (2026-11-14): effect curves and the UK on them, poverty and median income against the government's statistics, and engine speed (`docs/S11-PLAN.md`, done). The UK's month is 14 to 16 ms on four threads with the poverty measures |
| S12 Pages, the policy web, political capital, a map | At the owner's request (2026-11-14) (`docs/S12-PLAN.md`, done). The client it made was rejected the next day as a dashboard with pages; political capital, an engine rule, stayed |
| S13 The web is the game | The owner's brief (2026-11-14, `docs/S13-PLAN.md`, done): one full-screen board of policies, statistics and groups of voters, everything opened by clicking a node; looking ahead (forecasts, an effects table); nineteen real policies introduced and repealed; a whole term played as a check, and the balance report (`docs/S13-BALANCE.md`); the public finances made to matter |
| S14 After the first playtest | The owner played on 2026-11-16 (`docs/S14-PLAN.md`, done): the board fixed to the screen, the groups as one ring with approval gauges, colours by what a thing is, a speed budget the checks enforce; the Python reference retired (the engine is the only implementation, `polisim serve`); a bridge that never makes the next month wait; Bank Rate, mortgages, slumps that last |
| S15 After the second playtest | "Better by quite a bit" (2026-11-16, `docs/S15-PLAN.md`, done): groups by belief, work and place; an Add policy sheet in place of the bubbles; search; twelve policies and twelve statistics more |
| S16 After the third playtest | 2026-11-16 (`docs/S16-PLAN.md`, done): political capital and approval back on the top bar; a first polish pass (24 faults listed, 20 fixed); belief groups sized from published segments |
| S17 The second polish pass | Asked for by the owner on 2026-11-16, done on 2026-11-22 (`docs/S17-PLAN.md`): contrast measured, one spacing scale, the keyboard inside popups and sheets, the top bar's order of giving way, every fold photographed at two sizes, a mod that adds what the model lacks; each with a check that keeps it fixed. Before it, two checks that failed now and then in CI were traced to their causes (a real fault in the bridge, and a speed budget that took no account of the machine) |
| S18 The look, to the genre's standard | Asked for by the owner on 2026-11-28, done the same day (`docs/S18-PLAN.md`): every pictogram made at the size it is shown, so sharp at any size and scale; a plate (a poster-style picture from the open pictograms) at the head of every question, of election night and of the end of a term; the country as a map on the Parliament sheet, from the ONS's open boundaries; the game's own icon and opening picture, and the whole screen on F11; each with a check that keeps it fixed. Two faults found on the way were fixed: the search's button lying over Add policy after a sheet opened, and the month's report drawn over the sheets |

## Decisions this plan rests on

**Standing rules of the owner's**, to be kept in every stage:

| Rule | Said |
|---|---|
| **Show, don't tell.** The interface is to be understood by using it, not by reading about it: no explainer notes on things, no instructions under controls, no sentences where a figure, a label, a state or a shape would do. A thing that needs a note to be understood is to be redesigned, not annotated. What stays in words is content (the model's own descriptions, a question's choices, a consequence about to happen) and what is asked for (a tooltip, the key, the keys) | 2026-11-28: "show dont tell, you should not have explainer notes on everything always remember this, ui should be intuitive not patronisingly explained". Held by `client/tests/folds_check.gd` (no muted text over 72 characters on any card, the model's own words apart) |
| **Open material before our own.** Use what is openly licensed and credited before making something from scratch | 2026-11-28 (`docs/S18-PLAN.md`) |

Taken by the owner on 2026-11-14:

| Question | Decision |
|---|---|
| First screen | Budget screen, one chart, one cause-and-effect view |
| Cause-and-effect view | A trace of one number now; a Democracy-style icon web in a later stage |
| Who tests S2 | The owner alone. Outside testers move to stage S4 |
| Branches | Create `main`; each stage arrives as one pull request |
| First build target | Windows (the owner's machine); Linux is kept working by CI |
| First real country | The United Kingdom (owner, 2026-11-14) |
| Owner testing | The owner cannot test builds or check licence pages for now (2026-11-14). Work continues; items that need the owner are listed as open, not skipped |
| After S8 (decision page, 2026-11-14) | Losing an election ends the game; descriptive blocs, not real parties; the judgements stand until data replace them; the Open Parliament Licence still to be checked before release; a play test within a week; Early Access decided after it; Steam Workshop with Early Access; no second country yet; closed source (`docs/S9-PLAN.md`) |

Earlier decisions (the 22-question ballot) are in
`research_notes/PoliSim engine architecture pathways/ballot_decisions.md`.

## How we work

- **One pull request per stage** into `main`, built up from small commits on the working
  branch. The owner reads and merges it; nothing reaches `main` any other way. (In practice
  stages S2 to S17 shared one branch; from here on a stage is a pull request again.)
- **Every milestone ends with something the owner can run** on Windows, downloaded from
  the pull request's CI run, plus a short note saying what to try.
- **CI is the gate.** A milestone is not done until CI is green on Windows and Linux:
  formatting, lints, the engine's tests, the behaviour tests in `tests/`, the recorded
  hashes, the hindcast check, and from S2 on a scripted test of the client. (Until stage
  S14.2 it also ran the Python reference's tests and random scenarios through both
  implementations.)
- **The specification is the definition.** Since stage S14.2 the engine is the only
  implementation: any change to simulation behaviour goes into the contract (`docs/spec/`)
  first, then the engine, and re-records the hashes on purpose. Features that only observe a
  run (the trace view, charts, history) must not change a state hash.
- **Benchmarks before optimisation.** Nothing is tuned without a measurement that says it
  matters.
- **This file is the memory.** Cloud sessions start with nothing but the repository, so
  each session begins by reading this file and the README, and ends by updating them.

## Stage S2: the playable shell

**Goal.** A Godot client in which the owner plays one five-year term of a stylised
country by setting taxes and spending, watching what happens, and asking why.

**Out of scope for S2.** Real data, regions, parties and elections, art, sound,
localisation, Steam, the icon web, multiplayer. The model stays the toy economy, rescaled
and renamed.

### Shape of the client

```
client/              Godot 4.7 project: scenes and GDScript for the interface
crates/godot/        Rust library loaded by Godot (godot-rust), the only bridge
crates/core/         the engine, unchanged in behaviour
```

- The interface is written in GDScript, because interface code changes constantly and
  GDScript reloads without a rebuild. Everything that computes is Rust.
- The bridge exposes one object to the interface: open a scenario, list levers, set a
  lever, advance time, read the latest results, read a history, explain a number, save,
  load, reload the model.
- The simulation runs on its own thread inside the Rust library. The interface thread
  only ever receives finished results, so a slow step can never freeze the window.
- The interface is generated from the model, not written for the toy. Levers come from
  the model's lever declarations; the budget screen comes from the flows into and out of
  the government sector; names, units and help text come from the model files. A
  different model should produce a different, working interface with no client change.

### Milestones

Status on 2026-11-14: M2.0 to M2.6 are built. Every "done when" that a script can check
passes in CI on Windows and Linux; the ones that need the owner at a Windows machine are
open.

| # | Milestone | What is built | Done when |
|---|---|---|---|
| M2.0 | Tracer bullet | The Rust library compiles against Godot 4.7 on Windows and Linux; a one-label scene opens the toy scenario, runs 12 months and shows the state hash; CI builds a Windows download | The hash on screen equals the recorded one, in a cloud screenshot and on the owner's machine |
| M2.1 | Shell | Simulation thread and results channel; a top bar with the date and advance buttons (month, quarter, year); a headline strip; the lever list generated from the model, with limits and units | A scripted client run of 60 months with lever changes gives the same hashes as the command-line runner |
| M2.2 | Budget screen | Revenue and spending lines generated from government flows, with this month, last month and change; levers edited in place, shown as pending until the next step; an end-of-term summary after month 60 | The owner can raise a tax, advance a quarter and see the budget lines move, without instructions |
| M2.3 | Chart | A time-series control drawn by hand: any national figure, several at once, policy changes marked on the time axis, values on hover | Any figure on the budget screen can be sent to the chart in one click |
| M2.4 | Trace | Engine: for any national figure, its inputs, their values last month and this month, and how much of the change each explains. Client: a panel that shows this and lets the player walk from a figure to its inputs | For figures that are sums, the parts add up to the change exactly; for others the unexplained remainder is shown, never hidden |
| M2.5 | Hot reload | Engine: reload the model files and carry the run's state across by name. Client: a reload button, and a panel that shows a model error as text instead of crashing | Editing a formula in a text editor and pressing reload changes the next month; a typo shows a readable error and the game continues on the old model |
| M2.6 | Term | The toy rescaled to a mid-sized country with an invented name; tooltips from the model's help text; money and percentages formatted for people; save and load; a one-page guide | The owner plays a full term on Windows unaided |

M2.0 comes first because it retires the largest unknowns at once: the Rust-to-Godot
bridge, the Windows build, and whether numbers survive the trip unchanged. If the bridge
library proves unworkable, the fallback is a small C interface to the engine with a thin
native shim; the last resort is the client driving the existing command-line session.

### Engine work S2 needs

All of it observes or restructures; none of it may change a state hash.

| Addition | Why | How it is tested |
|---|---|---|
| Previous-step copy of every national value | The trace compares this month with last | Hashes unchanged with it on |
| `explain(name)` | The trace view | Parts plus remainder equal the change; exact for whole-number sums |
| Model reload with state carried across | Hot reload | Reloading an unchanged model changes no later hash; reloading a changed one equals a fresh run of the new model from the same state |
| Descriptions for the interface: kinds, units, help text, which flows touch which sector | Generated screens | The client test checks a second, different model produces a working budget screen |
| A step-timing counter per phase | To know where time goes before anyone optimises | Printed by the runner's `--time` |

### How I check the client from the cloud

Godot 4.7.2 is installed in the `PoliSimEngineAndGame` cloud environment and renders on a
virtual display. For each milestone I run a scripted session, save screenshots and look
at them, and CI runs the same script without a display on Windows and Linux and compares
state hashes with the command-line runner. What I cannot check from here is how it looks
and feels on a real screen: font sizes, scaling on a high-resolution display, mouse
feel. That is the owner's part at each milestone.

### S2 exit test

1. The owner finishes a 60-month term on Windows without help from me.
2. The owner can explain one chain of cause and effect using the trace view, for example
   why a spending cut did not close the deficit.
3. An edited formula reloads without restarting the game.
4. The client gives the same state hashes as the command-line runner for the same inputs,
   on both systems, in CI.
5. The stage's pull request is merged.

The roadmap asked for outside players at this point. With one tester the first two tests
are weaker than intended, because the owner already knows the model. Outside testing is
therefore the first item of S4, when households make "who gains and who loses" visible.

### Risks in S2

| Risk | Sign | Response |
|---|---|---|
| The bridge library's threading support is still marked experimental | Crashes or build failures in M2.0 | The design never touches Godot objects off the main thread; fall back as described above |
| The cloud renders in software, the owner's machine does not | Layout or fonts look different on Windows | Owner screenshots at every milestone; fixed minimum window size |
| Windows blocks an unsigned download | A SmartScreen warning | Expected; the guide says how to proceed. Signing waits until release |
| The interface grows faster than the game | Milestones slipping on polish | Each milestone has one "done when"; anything else goes to a list for later |
| The trace is confusing for figures that are not sums | The owner cannot explain a chain | Show the remainder honestly; prefer walking through sums, which are exact |

## What I need from the owner

As it stands on 2026-11-28, after S18:

| When | What | Why |
|---|---|---|
| Now | Play the newest Windows build (the `PoliSim-windows` download on the latest CI run) at the window size you use, once with the keyboard (Tab through a popup, Esc out of it) and once on the whole screen (F11). Open Parliament and a question, and say what you think of the map and the plates | S17's checks measure contrast, spacing, fit and focus, and S18's that pictures are sharp and the map is right. How it looks and feels on a real screen is yours to say |
| Now | Say whether you want more of S18's kind: a paper texture under the board, motion when a month turns, music. Each was looked at and left for you to ask for (`docs/S18-PLAN.md`, Decisions) | They are matters of taste, and a texture sits under text whose contrast S17 measured |
| Now | Say whether each new game should have a seed of its own | Today every game of a scenario meets its chance events in the same months |
| Now | Say whether the dilemmas' political costs are the right size, and whether the S11 effect curves feel right in play | Open since S9 and S11 |
| Before any release | Open the licence pages in `docs/data/first-country-licences.md` (the Open Parliament Licence among them) and confirm them | I could only read search summaries of those pages |
| When you want outside eyes | Name one or two people to play it cold | Every playtest so far has been yours, and you know the model |

The list as it was written after S1, kept for the record (the first-country and election-study
rows were settled on 2026-11-14):

| When | What | Why |
|---|---|---|
| Now | In GitHub: Settings, General, Default branch, switch to `main` | So new sessions and pull requests start from the trunk |
| M2.0 | Download the Windows build from the CI run, start it, send a screenshot | Confirms the bridge and the build on a real machine |
| M2.0 | Run the bundled benchmark program and paste its output | Stage S0 still lacks numbers from real hardware |
| Each milestone | Ten minutes with the new build; say what confused you | The only feedback on feel I can get |
| End of S2 | Play a full term; explain one chain; read and merge the pull request | The exit test |
| Before S3 | Choose the first country | Everything in S3 depends on it |
| Before S3 | Open the licence pages listed in `docs/data/first-country-licences.md` for that country and confirm them, or tell me to proceed on the summaries at your risk | I could only read search summaries of those pages |
| Before S5 | Decide whether to ask the British Election Study (or its equivalent elsewhere) for permission | Without it the voter model uses published results only |

## After S2, in outline

Each stage gets a plan like the one above when it starts. Order and exit tests follow the
roadmap; the notes here record what has changed since it was written.

| Stage | Builds | Changed by what we now know |
|---|---|---|
| S3 National books | A real country's sector accounts, budget by function, cohort table, 10 to 15 industries, one rest-of-world sector, and a one-command data pipeline | Needs regions, industries and cohort ageing in the model format, so it opens with a format 1 proposal. The Python module is built here, for calibration |
| S4 Households | A synthetic population of 20,000 then 100,000 households; real tax and benefit rules; alignment to the cohort table | Opens with outside testers. The engine already steps 100,000 households in 12 ms on toy rules; the open question is rule depth, which S0 put at 55 to 71 ms for a deep system |
| S5 Politics | Voters, parties as blocs, a legislature, bills that can fail | Voter data needs a licence decision first. The icon web belongs here or in S6 |
| S6 Depth and calibration | Full industry detail, regions, trading blocs, low, central and high presets, sensitivity screening | Threads and other optimisation only if measurements ask for them |
| S7 Content and public surface | Interface depth, mod documentation, save migration, Workshop, Early Access, a second country, opening the engine's source | Business decisions (price, store page, timing) arrive here |

## Loose ends carried forward

| Item | From | Plan |
|---|---|---|
| Data licences not confirmed | S0 | Owner's check before S3; see the table above |
| No benchmark on real hardware | S0 | Owner runs the bundled benchmark at M2.0 |
| Python module not built | S1 | Built in S3, when calibration needs it |
| No overflow checks in the S0 benchmark | S0 | Done in S4.4: with overflow checks and the 2024-25 rules, 100,000 households take 68 ms a month (`models/uk/households/README.md`) |
| Saves break when any model file changes | S1 | Done in S7.0: save format 1 follows the model when its files change (`docs/spec/04-save-format-v0.md`) |
| A loaded game has no household figures for the month it was saved in: a group's Households fold is empty until a month has run (the save keeps the simulation's lasting values, not each month's per-household results) | S13, found in review of the pull request on 2026-11-22 | The client now says so in the fold. The fix is the engine's: keep or work out again the last month's per-record results on load. For its own stage, since it touches what a save holds |
| Engine timings are for shallow rules only | S1 | Done in S4.4: the UK model with 20,000 households takes about 15 ms a month, with 100,000 about 68 ms, on a four-core server |
