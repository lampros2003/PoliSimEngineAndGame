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

## Decisions this plan rests on

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

Earlier decisions (the 22-question ballot) are in
`research_notes/PoliSim engine architecture pathways/ballot_decisions.md`.

## How we work

- **One pull request per stage** into `main`, built up from small commits on the working
  branch. The owner reads and merges it; nothing reaches `main` any other way.
- **Every milestone ends with something the owner can run** on Windows, downloaded from
  the pull request's CI run, plus a short note saying what to try.
- **CI is the gate.** A milestone is not done until CI is green on Windows and Linux:
  formatting, lints, the oracle's tests, the engine's tests, random scenarios through both
  implementations, and from S2 on a scripted test of the client.
- **The oracle stays the definition.** Any change to simulation behaviour goes into the
  contract and the oracle first, then the engine. Features that only observe a run (the
  trace view, charts, history) live in the engine alone and must not change a state hash.
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
| Engine timings are for shallow rules only | S1 | Done in S4.4: the UK model with 20,000 households takes about 15 ms a month, with 100,000 about 68 ms, on a four-core server |
