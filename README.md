# PoliSim

A political and economic simulation game in which the player is head of government, with
an economy and a population simulated in real units. This repository holds the simulation
engine's specification, its reference implementation and the research behind the design.

The game does not exist yet. What exists is stage S0 of the roadmap: a written contract
for the engine, a model-file format, a toy economy and an executable reference that the
real engine will be tested against.

## Layout

| Path | What it is |
|---|---|
| `docs/spec/` | The engine contract, model-file format 0, formula language 0 and the toy model with its target patterns |
| `oracle/` | The reference evaluator: a deliberately naive Python implementation of the contract. It is the test oracle for the engine, not a prototype of it |
| `models/toy/` | A three-sector economy with 1,000 household records, written in the model-file format |
| `bench/s0/` | Rust micro-benchmarks and their recorded results |
| `docs/data/` | Licence status of the data sources for the first real country |
| `tools/` | Generators for synthetic data |
| `reports/`, `research_notes/` | The architecture research report and the notes it was written from |

## Run it

The oracle needs Python 3.11 or later and nothing else.

```bash
cd oracle
```

```bash
python -m unittest discover -s tests
```

```bash
python -m polisim_oracle run ../models/toy/scenarios/baseline.toml --out baseline.csv
```

The benchmarks need a Rust toolchain:

```bash
cargo run --release --manifest-path bench/s0/Cargo.toml
```

## Where things stand

Stage S0 exit criteria, from the roadmap in `reports/PoliSim engine architecture pathways.md`:

| Criterion | State |
|---|---|
| Accounting identities hold exactly over 200 steps | Met: checked on every step of 360-step runs |
| Every target pattern reproduced | Met: 13 patterns, see `docs/spec/03-toy-model.md` |
| Benchmark numbers recorded | Met on a cloud machine, see `bench/s0/RESULTS.md`; not yet run on a laptop |
| Data licences confirmed per source | **Not met**: see `docs/data/first-country-licences.md` |

Next is stage S1: the Rust core (loader, unit check, plan compiler, block-wise evaluator,
phased step, state hash, saves), required to match the oracle's hash on every step.
