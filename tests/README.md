# Behaviour tests

What the models and the formula language must do, run on the engine through
`polisim serve` (`docs/spec/09-serve.md`) by way of `tools/engine.py`. Python 3.11 or later,
standard library only:

```bash
cargo build --release
python -m unittest discover -s tests
```

The suite takes one to two minutes (179 tests; 42 s to 112 s on one Windows PC). Each model is loaded
once per test module and every simulation is a run inside its process.

Stage S14.5 added `test_economy.py` (22 tests): the tax rise and the State Pension spread,
interest rates, slumps that last, the borrowing chance, homelessness and productivity. The
eight strategies of `docs/S13-BALANCE.md` are played by `python tools/uk/strategies.py`.

## Where the reference implementation's tests went

Until stage S14.2 these tests ran on the Python reference implementation (`oracle/`), 196
tests in 40 to 50 minutes. Each one is now in one of three places:

- **moved**: in this folder, unchanged but for the import of `engine` instead of
  `polisim_oracle` (and the repository root one folder up), and passing on the engine;
- **moved, rewritten**: in this folder, stating the same behaviour through `evaluate` or a
  small model, because the original read the reference implementation's own objects;
- **in Rust**: the engine already had the same test (named below), or it was ported there.

Before the reference implementation was removed, the files with rewritten or removed
tests (`test_language`, `test_format1`, `test_raking`, `test_bills`, `test_dilemmas`,
`test_lags`, `test_mods`, `test_situations`) were run on both implementations and passed on
both; the files moved unchanged had passed on it at the commit before, and all pass on the
engine.

| Old file | Tests | Where they went |
|---|---:|---|
| `test_uk.py` | 46 | moved, all |
| `test_households.py` | 12 | moved, all |
| `test_politics.py` | 10 | moved, all |
| `test_groups.py` | 10 | moved, all |
| `test_policies.py` | 18 | moved, all |
| `test_finances.py` | 5 | moved, all |
| `test_patterns.py` | 17 | moved, all |
| `test_elections.py` | 4 | moved, all (they check the election data only) |
| `test_raking.py` | 7 | 6 moved (`TestModel`); `SharedCases.test_every_case` in Rust: `crates/core/tests/raking.rs`, `shared_cases_match_their_expectations` |
| `test_format1.py` | 16 | 14 moved; `Loading.test_bad_declarations_are_refused` and `test_a_data_file_must_hold_every_cell_once` in Rust: `crates/core/tests/format1.rs`, `bad_declarations_are_refused` and `a_data_file_must_hold_every_cell_once` |
| `test_language.py` | 33 | 27 moved, 19 of them rewritten (below); 6 in Rust (below) |
| `test_bills.py` | 4 | 3 moved (`UnitedKingdom`); `SharedCases.test_every_case` in Rust: `bills.rs`, `shared_cases_match_their_expectations` |
| `test_dilemmas.py` | 3 | 2 moved (`Loader`); `SharedCases.test_every_case` in Rust: `dilemmas.rs`, `shared_cases_match_their_recorded_outcomes` |
| `test_lags.py` | 3 | 2 moved (`Loader`); `SharedCases.test_every_case` in Rust: `lags.rs`, `shared_cases_match_their_recorded_outcomes` |
| `test_mods.py` | 3 | `ExampleMod` moved; `SharedCases.test_mods_are_recorded_in_order` moved as `Order.test_mods_are_recorded_in_order`; `SharedCases.test_every_case` in Rust: `mods.rs`, `shared_cases_match_their_recorded_outcomes` |
| `test_situations.py` | 2 | `UnitedKingdom` moved; `SharedCases.test_every_case` in Rust: `situations.rs`, `shared_cases_match_their_recorded_outcomes` |
| `test_conformance.py` | 2 | in Rust: `conformance.rs`, `engine_reproduces_every_recorded_case` and `engine_reproduces_every_recorded_format1_case` |
| `test_random_models.py` | 1 | in Rust: `random_models.rs`, `random_models_match_the_recorded_hashes_on_one_two_and_eight_threads` |
| **All** | **196** | **179 moved (19 of them rewritten), 17 in Rust, none dropped; 2 parts ported to Rust** |

`test_language.py` in detail. Its old tests evaluated formulas in a scope built by hand
from the reference implementation's classes (`Runtime`, `Decl`, `Entity`, `Table`); the
scope is now a small model (`SCOPE`) and every formula goes through the engine's
`evaluate`:

| Old test | Where it went |
|---|---|
| `Arithmetic` (8), `Units` (4), `TablesAggregatesAndLags.test_weighted_aggregates`, `test_columns_cannot_leak_into_national_formulas` | moved, rewritten: the same formulas and results |
| `TablesAggregatesAndLags.test_marginal_schedule` | moved, rewritten: the schedule in a formula; the function on its own (rounding at the band edges, bands out of order) ported to Rust: `crates/core/tests/language.rs`, `marginal_schedule` |
| `TablesAggregatesAndLags.test_prev_reads_last_step` | moved, rewritten: between steps the engine's `prev(x)` is `x`, so `prev` is read by formulas in a model run for a step |
| `TablesAggregatesAndLags.test_random_draws_depend_only_on_seed_stream_record_and_step` | moved, rewritten (in [0, 1), the same for the same seed, different the next step); the exact value, Philox of seed, stream, record and step, ported to Rust: `language.rs`, `a_draw_is_philox_of_seed_stream_record_and_step` |
| `TablesAggregatesAndLags.test_philox_known_answers` | in Rust: `crates/core/src/rng.rs`, `philox_known_answers` (the same three vectors) |
| `Loader` (8 of 9) | moved: they load small models from files |
| `Loader.test_money_is_scaled_from_the_number_as_typed` | in Rust: `crates/core/src/model.rs`, `money_is_scaled_from_the_number_as_typed` (the same cases) |
| `Exp.test_within_two_units_in_the_last_place_of_the_c_library`, `Exp.test_limits` | in Rust: `crates/core/src/program.rs`, `exp_is_within_two_units_in_the_last_place` (a sweep over the range, and the same limits) |
| `LnSqrtPow.test_ln_within_two_units_in_the_last_place_of_the_c_library`, `LnSqrtPow.test_limits` | in Rust: `program.rs`, `ln_is_within_two_units_in_the_last_place` and `sqrt_and_pow_at_their_edges` (the same limits) |
| `Exp.test_in_a_formula`, `LnSqrtPow.test_in_a_formula` | moved, rewritten |

The reference implementation also defined the reserved function names, which
`crates/core/tests/format1.rs` read from its source; they are now pinned by
`conformance/functions.txt`, written from it before it was removed.
