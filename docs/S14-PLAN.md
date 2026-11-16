# Stage S14: after the first playtest

## Context

The owner played the S13 board on 2026-11-16 and reported:

1. The interface is unintuitive and sloppy in places.
2. The panel on the right (the month's report) pushes the whole board to the left.
3. The board can still be dragged and zoomed. It should simply be the screen.
4. The groups as shields are cluttered. He wants one ring of arcs, one arc a group, with an
   approval arc round each: green good, yellow mixed, red bad.
5. Statistics and situations should be colour-coded: blue neutral, green good, red bad.
   Policies stay as they are.
6. The interface is clunky and slow.
7. The Python oracle is no longer needed and slows development. The engine's economics and
   graph should be developed properly, fast and responsive, with whatever features it needs.

What three surveys of the code found (so the plan stands on facts):

- **The shift.** The report is 380 px wide and sets the board's right edge 412 px in
  (`main.gd`, `board.offset_right`). Each month the board is laid out again up to three
  times, each a 0.45 s glide.
- **Slow by construction.** Every event from the engine redraws everything (`_refresh` on
  each of about forty effects events a month, plus forecasts). The link layer redraws every
  frame while a popup is open. A month plays 0.11 s + 0.18 s + 0.45 s of closing animations
  before the engine is even asked, and about a second more after it answers.
- **The bridge.** After every request the bridge copies the whole history of every row to
  the interface, and that copy grows each month. A forecast runs on the game's own worker
  thread, so it blocks the next month and cannot be cancelled. The effects table uses two
  threads, starts 1.5 s after a month, and is recomputed from nothing each time.
- **The oracle.** 132 behaviour tests exist only in Python and take 40 to 50 minutes. The
  hindcast, one step of calibration, the recorded hashes and the comparison tool all run on
  it. It takes about a second a month; the engine takes 17 to 20 ms.
- **The look.** Links are blue for a rise and red for a fall, which says nothing about good
  or bad. Indicators are all the same ink. The policy popup is 1,100 px wide and half empty.

## Decisions

### The board

| Question | Decision |
|---|---|
| Moving the board | It cannot be moved. No drag, no wheel zoom, no arrow keys, no "See the whole board". The board fills the window under the top bar at every size, and every node has its label at rest from 1366x768 up |
| What may change the board's size | Only the window. Nothing docks. The report, notices and popups float over it |
| The month's report | A popup window over the board, opened only when the month has something to tell: a bill voted or refused, a situation begun or ended, an election, a policy come into force. An ordinary month shows one line under the date for three seconds. The date on the top bar reopens the last report. Several months played at once give one report |
| Notices | One place (a line under the top bar), gone after a few seconds or on a click. A voted-down bill is told once, in the report, not also in a notice |
| Groups | One ring round the centre. Each group is an arc of the ring; families are separated by a gap and named once. An arc's length is the group's share of the electorate within its family, with a least length so every arc can carry its pictogram. Just outside each arc runs its approval arc, filled in proportion to approval and coloured green, yellow or red. Name and figure show on hover and stay for the largest groups. A click opens the group's popup as now |
| What is good approval | The scenario says (`[play.web]` `approval_good`, `approval_bad`). The UK: green from 38%, red below 28%, yellow between. A group with no governing party to back (Northern Ireland) is grey |
| Statistics | An indicator's colour says what kind of thing it measures, and does not change in play: red for a bad thing (crime, unemployment, poverty, debt), green for a good thing (output, healthy life, homes built), blue for the rest. The scenario's `better` decides: `low` is a bad thing, `high` a good one, none is neutral. The small triangle for last month's movement stays |
| Situations | Green if good, red if bad, blue if neither (a question waiting keeps its ochre). They sit in one strip under the top bar, which is always there, so they never move a node |
| Policies | As they are |
| Links | Green when the effect is good for what it reaches, red when bad, blue when neither can be said. Width for strength. A sign (+ or -) at the arrowhead says rise or fall, so colour never has to carry two meanings |
| Popups | Sized to what they hold, never wider than 640 px at 1080p. A policy opens with its main control, the cost in capital and the vote it would get. "In a year" takes its place beside the control only once the control has moved. Further controls (thresholds, allowances) open under "More". No scroll bar inside a popup at 1080p |
| A key | "?" on the top bar opens a one-page key: what each shape, colour and arc means |

### Speed

A budget the checks enforce (`client/tests/perf_check.gd`), measured on this PC at 1920x1080:

| Action | Budget |
|---|---|
| Click to popup fully open | 120 ms |
| Popup close | 80 ms |
| "Next month" to the board showing the new month | 150 ms (the engine takes about 20) |
| "Year" (twelve months) | 1 s, with the date counting |
| Hover to links | The same frame, from the table already held |
| A forecast after a control moves | 250 ms, and never blocks "Next month" |
| Idle frame with a popup open | Nothing redrawn |

How: an engine event redraws only what it changed; the month's closing and opening
animations overlap the engine's work instead of preceding it; layers redraw on change, not
every frame; popup contents are built once and reused.

### The engine

| Question | Decision |
|---|---|
| The oracle | Retired. The Rust engine is the only implementation and the specification is `docs/spec` |
| Its tests | Kept, and run on the engine. The 132 behaviour tests move to `tests/` and drive the engine through a new `polisim serve` (lines in, JSON out: set a lever, step, read a row, read a column, evaluate a formula). The suite should take about two minutes instead of forty. Tests of the oracle's own internals go where the engine already has the same test, and are listed |
| Recorded hashes | Kept as pins of the engine's own behaviour, recorded with `polisim run`. `conformance/` stays as fixtures. The comparison tool and the fixture generators go |
| Hindcast and calibration | Run on the engine through the same `serve`. The committed hindcast results must be reproduced exactly |
| Determinism | Kept: the same hash at any thread count, integer money, the counter-based random numbers, saves that replay exactly. These are for the game, not for the oracle |
| The interface thread | The bridge sends only the new month's rows, not the whole history each time |
| Forecasts | On their own thread, the latest request wins, a new month or a new request cancels the old |
| The effects table | All cores but one. It starts at once after a month, with the policy under the pointer first. The last table stays in use until the new one replaces it, and is kept in the save so links are there from the first frame of a loaded game |
| A month | Profiled first (`crates/core/examples/session_time.rs`), then the allocations the profile shows are removed and the state hash is computed only when it is asked for. No change to any result |
| The graph | The engine answers "what does this reach, by what path" itself (`reach`, `path`), so the client's own search goes |

### The economy

The playtest report's open faults and the model's own list of weaknesses, in the order they
hurt play:

| Fault | Decision |
|---|---|
| No interest rate reaches anyone but the Treasury | A Bank Rate set by a rule (inflation and slack), a mortgage rate that follows it and the gilt yield, and business investment that reads the cost of borrowing. Households hold mortgages by tenure and age from published shares. The lenders' premium then reaches voters' incomes |
| The borrowing line is a cliff | The lenders' crisis becomes a chance that rises with borrowing above the start, not a line at 1.2 points; the voters' curve loses its kink |
| A slump heals in months | Employment follows output with a lag (firms hoard labour, then shed it), and long unemployment lowers the workforce for a time |
| A large tax rise first worsens the deficit | Found and fixed, with a test |
| Pensioner poverty falls nine points in one month | The synthetic households' pensions are spread as the published distribution is, so they do not cross the line together |
| No homelessness and no productivity on the board | Two new statistics, asked for by the owner. Homelessness (households in temporary accommodation, from the published 2024 figure) moves with rents, homes built, social housing, benefits and unemployment; it is a bad thing, so red. Productivity (output per hour or per job against 2024) moves with business and public investment, school results and health; it is a good thing, so green, and it feeds pay and output over time |
| Austerity only ties with doing nothing | Re-measured after the above, then tuned: the eight strategies are run again |

Each change keeps the 2024 base month to the published figures and is tested on the engine.
The hindcast is fitted again where the economy changes, and its error must not grow.

## Stages

Three lanes run at once, each built by an Opus agent from a brief, checked and published by
me one commit a stage. The client works in the checkout; the two engine lanes each work in
a private copy of the repository and their files are copied back.

| # | Stage | Lane and files | Done when |
|---|---|---|---|
| S14.1 | **The board as the screen**: fixed, the group ring, colours, the report as a popup, popups to size, the key | Client: `client/scripts`, `client/tests`, `[play.web]` in the 2025 scenario | Every scripted check passes (rewritten where it tested zoom or shields); screenshots at 1366x768, 1920x1080 and 2560x1440 looked at; no label missing at rest |
| S14.2 | **The oracle retired**: `polisim serve`, the tests on the engine, hindcast and calibration on the engine, CI, the spec's wording | Engine tools: `crates/cli`, `crates/core/tests`, `tests/`, `tools/`, `oracle/` removed, `.github/workflows`, `docs/spec`, `README.md` | `models/` is byte for byte unchanged; every recorded hash is reproduced; the moved tests pass on the engine; the hindcast check passes; a table says where each old test went |
| S14.3 | **A responsive engine**: the bridge's history, forecasts and effects off the worker, the month profiled, `reach` and `path` | Engine: `crates/core/src`, `crates/godot/src`, `crates/core/examples` | No recorded hash changes; before and after timings in the status table; the bridge's contract with the client only grows |
| S14.4 | **Speed, joined**: the client uses the new bridge; the budget above is enforced | Client, after S14.1 and S14.3 | `perf_check` passes; a whole term through the board still passes |
| S14.5 | **The economy**: interest rates, the borrowing chance, slumps that last, the two bugs, the strategies run again | Model: `tools/uk`, `models/uk`, `tests/`, after S14.2 | Tests on the engine for each mechanism; the base month to the published figures; hindcast error no worse; `docs/S13-BALANCE.md` gains "After S14.5" |
| S14.6 | **Finish**: the guide, spec 05, the wiki page, the build skill, a last look at every screen | Docs | The guide describes the screen as it is |

## Verification

After every stage, from the repository root (close the game first; it locks the bridge DLL):

- `cargo fmt --all --check`; `cargo clippy --workspace --all-targets --release -- -D warnings`; `cargo test --release --workspace`
- Until S14.2 is in: the oracle suite and `tools/diff_engine.py` as before. After: `python -m unittest discover -s tests` on the engine
- `python tools/uk/hindcast.py --check`
- `python tools/build_client.py --godot <console exe>`; `python tools/check_client.py --godot <console exe>`
- Screenshots of the board, each popup and each sheet at three sizes, looked at before a stage is accepted

## Status

| # | Status |
|---|---|
| S14.1 | Under way |
| S14.2 | Done. `oracle/` is gone; the engine is the only implementation and `docs/spec` the specification (00 §12, "One implementation, pinned"). `polisim serve` (`crates/cli/src/serve.rs`, `docs/spec/09-serve.md`) holds one or more runs of a loaded model and answers one request a line in JSON: set, step, get a column, evaluate, votes, symbols. `tools/engine.py` gives the tests and the UK tools the calls they had. Of the 196 old tests, 179 moved to `tests/` and run on the engine (19 rewritten through `evaluate`), 17 were already in Rust, parts of 2 are new Rust tests (`crates/core/tests/language.rs`); none lost (`tests/README.md` lists each). The suite takes about a minute, from forty. The hindcast, the calibration's base month and `screen.py` run on the engine; the hindcast's committed results and all eight recorded hash files are reproduced (`tools/record_goldens.py --check`). `models/` is unchanged but for README wording. The comparison tool and the fixture generators are removed; `conformance/` stays as frozen fixtures. CI runs the engine's tests, the Python suite, the recorded hashes and the hindcast check |
| S14.3 | Under way |
| S14.4 | Planned |
| S14.5 | Planned |
| S14.6 | Planned |
