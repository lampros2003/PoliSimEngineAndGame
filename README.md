# PoliSim

A political and economic simulation game in which the player is head of government, with
an economy and a population simulated in real units. This repository holds the simulation
engine, the specification it implements, a reference implementation it is tested against,
and the research behind the design.

You govern the United Kingdom from January 2025: a monthly stock-flow model of the
economy and public finances calibrated to 2024, 20,000 synthetic households under the
2024-25 tax and benefit rules, 600 types of voter choosing between nine blocs, 650
constituencies, a House of Commons that votes on your policy changes, and a general
election in July 2029. The Godot client shows the budget, who gains and who loses, the
polls and seats, and why any figure changed. Mods add to the model; saved games survive
changes to it. `docs/GUIDE.md` is the player's guide; `docs/MODDING.md` shows how to make
a mod.

## Layout

| Path | What it is |
|---|---|
| `docs/spec/` | The engine contract, model formats 0 and 1, the formula language, save formats, the game client, mods, text for translations, and the toy model with its target patterns |
| `crates/core/` | The engine (Rust): model loader, type and unit checker, bytecode compiler, block-wise interpreter, step loop, saves |
| `crates/cli/` | `polisim`, the command-line runner and interactive session |
| `crates/godot/` | The bridge that runs the engine inside the Godot client |
| `client/` | The Godot 4.7 game client (GDScript) and its scripted tests |
| `oracle/` | The reference evaluator: a deliberately naive Python implementation of the contract. It defines the behaviour; the engine is tested against it |
| `models/uk/` | The United Kingdom: national accounts, population, industries, households, voters, trade, generated from published data by `tools/uk/` (`models/uk/README.md`) |
| `mods/` | Mods the game ships with: `wealth_tax`, the example in `docs/MODDING.md` |
| `models/toy/` | A three-sector economy with 1,000 household records, written in the model-file format |
| `models/valmora/` | The same economy scaled to an invented country, where the client was first built |
| `models/mini/` | A tiny model with different names, used to test that the client adapts to any model |
| `models/cohort/`, `models/raking/` | Test models for format 1: a population by region, sex and age; weights raked to targets |
| `conformance/` | Formulas with the result the oracle gives for each; both implementations check every line |
| `tools/` | Synthetic data generators and `diff_engine.py`, which runs random scenarios through both implementations |
| `bench/s0/` | Stage S0 micro-benchmarks and their recorded results |
| `docs/PLAN.md`, `docs/S3-PLAN.md` to `docs/S7-PLAN.md` | The working plan and each stage's plan: what is built, how it is checked, and what the owner needs to do |
| `docs/data/` | Licence status of the data sources for the first real country |
| `reports/`, `research_notes/` | The architecture research report and the notes it was written from |

## Play

**The game client.** On Windows, download `PoliSim-windows` from the latest CI run of the
branch (Actions tab), unpack it and run `PoliSim.bat`. `docs/GUIDE.md` explains the screen.
To run it from the repository instead, with Godot 4.7.2 installed:

```bash
cargo build --release -p polisim-godot
```

```bash
python tools/build_client.py --godot godot
```

```bash
godot --path client
```

**In a terminal**, with only a Rust toolchain (1.86 or later; the client's bridge needs 1.94):

```bash
cargo run --release -p polisim-cli -- play models/uk/scenarios/2025.toml
```

Then, for example: `step 12`, `set basic_rate 0.25`, `step 24`, `levers`, `help`.

## Run and test

A scripted run, written as CSV (money in whole pence, so the file is exact):

```bash
cargo run --release -p polisim-cli -- run models/toy/scenarios/baseline.toml --out baseline.csv
```

The engine's tests: recorded hashes, the conformance corpus, save and resume.

```bash
cargo test --release --workspace
```

The oracle's tests need Python 3.11 or later and nothing else:

```bash
cd oracle
```

```bash
python -m unittest discover -s tests
```

Random scenarios through both implementations, compared byte for byte (from the
repository root, after `cargo build --release`):

```bash
python tools/diff_engine.py --count 200
```

## Where things stand

The roadmap is in `reports/PoliSim engine architecture pathways.md`.

Stages S0 to S10 are done, except what waits for the owner (the Windows play test of S2
and the business decisions of S7): `docs/PLAN.md` says where each stage stands, and
`docs/S3-PLAN.md` to `docs/S10-PLAN.md` hold their milestones. The tables below are the
first stages' exit criteria.

**Stage S0 (specification, oracle, data gate)**

| Criterion | State |
|---|---|
| Accounting identities hold exactly over 200 steps | Met: checked on every step of 360-step runs |
| Every target pattern reproduced | Met: 13 patterns, see `docs/spec/03-toy-model.md` |
| Benchmark numbers recorded | Met on a cloud machine, see `bench/s0/RESULTS.md`; not yet run on a laptop |
| Data licences confirmed per source | **Not met**: see `docs/data/first-country-licences.md` |

**Stage S1 (the Rust core)**

| Criterion | State |
|---|---|
| Engine matches the oracle on 1,000 random scenarios | Met: 708 finished, 84 failed part-way at the same step, 208 refused by both; 15,098 steps identical byte for byte |
| Save, load and continue equals an uninterrupted run | Met: tested at six save points, including across a policy change |
| Identical results on Windows and Linux | Met: CI runs the engine's tests and 150 random scenarios through both implementations on each system |
| Step time at ten times toy size | 1.2 ms per step at 10,000 households, against a target of well under a second per turn. See the timings below |
| A term is playable from the command line | Met: `polisim play` |
| Python module | **Not built.** The runner's CSV serves analysis for now |

Engine step time for the toy model's rules, one thread, default build, best of three runs
on a shared cloud machine (Intel Xeon at 2.1 GHz). Not yet measured on a laptop.

| Household records | Milliseconds per step |
|---:|---:|
| 1,000 | 0.14 |
| 10,000 | 1.2 |
| 100,000 | 12 |
| 1,000,000 | 153 |

The oracle takes about 17 ms per step at 1,000 households. Each engine step includes
posting, the identity checks and a SHA-256 hash of the state. These timings are from stage
S1, before any optimisation. Stage S10 (`docs/S10-PLAN.md`) added threads, register reuse
and shared work computed once, with every result unchanged. The full UK model (20,000
households, 600 voter types, 650 seats) now takes 17 to 20 ms a month on four threads.

**Stage S2 (the playable shell)**

| Criterion | State |
|---|---|
| The client gives the same state hashes as the runner, on Windows and Linux, in CI | Met: four scripted sessions, see `docs/spec/05-game-client.md` |
| An edited formula reloads without restarting the game | Met: tested with a typo and with a real change |
| The owner plays a full term on Windows unaided | **Not done**: the owner cannot test at present |
| The owner can explain one chain of cause and effect with the trace view | **Not done**: same reason |

Stage S3, the United Kingdom's national books, is under way: milestones S3.0 to S3.6 are done (data pipeline, UK model v0, playable UK, 2005-2024 hindcast, model format 1 with dimensions, the population by region, sex and age, and 15 industries). The status is in `docs/S3-PLAN.md`.
