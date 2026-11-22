//! The engine must reproduce the recorded state hashes on every step (they pin its
//! behaviour; tools/record_goldens.py re-records them):
//! the toy model's baseline, the first two years of the UK model, the cohort test model and
//! the households.

use std::path::PathBuf;
use std::sync::Arc;

use polisim_core::{Simulation, load_scenario, pyfmt};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

#[test]
fn baseline_matches_the_recorded_hashes() {
    let scenario = load_scenario(&root().join("models/toy/scenarios/baseline.toml")).unwrap();
    let recorded = std::fs::read_to_string(root().join("models/toy/golden/baseline.hashes.csv")).unwrap();
    let golden: Vec<&str> = recorded.lines().skip(1).map(|line| line.split(',').nth(1).unwrap()).collect();
    assert_eq!(golden.len(), 240);

    let mut sim = Simulation::new(Arc::new(scenario.model.clone()), scenario.config()).unwrap();
    for (step, want) in golden.iter().enumerate() {
        let row = sim.step().unwrap();
        assert_eq!(row.step, step as u64);
        assert_eq!(pyfmt::hex(&row.hash), *want, "state hash differs from the recorded hash at step {step}");
    }
}

#[test]
fn uk_matches_the_recorded_hashes() {
    let scenario = load_scenario(&root().join("models/uk/scenarios/2025.toml")).unwrap();
    let recorded = std::fs::read_to_string(root().join("models/uk/golden/2025.hashes.csv")).unwrap();
    let golden: Vec<&str> = recorded.lines().skip(1).map(|line| line.split(',').nth(1).unwrap()).collect();
    assert_eq!(golden.len(), 24);

    let mut sim = Simulation::new(Arc::new(scenario.model.clone()), scenario.config()).unwrap();
    for (step, want) in golden.iter().enumerate() {
        let row = sim.step().unwrap();
        assert_eq!(pyfmt::hex(&row.hash), *want, "UK state hash differs from the recorded hash at step {step}");
    }
}

#[test]
fn cohort_matches_the_recorded_hashes() {
    // Format 1: dimensions, sums, indexes, coordinates and cohort ageing.
    let scenario = load_scenario(&root().join("models/cohort/scenarios/base.toml")).unwrap();
    let recorded = std::fs::read_to_string(root().join("models/cohort/golden/base.hashes.csv")).unwrap();
    let golden: Vec<&str> = recorded.lines().skip(1).map(|line| line.split(',').nth(1).unwrap()).collect();
    assert_eq!(golden.len(), 36);

    let mut sim = Simulation::new(Arc::new(scenario.model.clone()), scenario.config()).unwrap();
    for (step, want) in golden.iter().enumerate() {
        let row = sim.step().unwrap();
        assert_eq!(pyfmt::hex(&row.hash), *want, "cohort state hash differs from the recorded hash at step {step}");
    }
}

#[test]
fn uk_households_match_the_recorded_hashes() {
    // 20,000 synthetic households under the 2024-25 tax and benefit rules (stage S4.2).
    let scenario = load_scenario(&root().join("models/uk/households/scenarios/base.toml")).unwrap();
    let recorded = std::fs::read_to_string(root().join("models/uk/households/golden/base.hashes.csv")).unwrap();
    let golden: Vec<&str> = recorded.lines().skip(1).map(|line| line.split(',').nth(1).unwrap()).collect();
    assert_eq!(golden.len(), 3);
    let mut sim = Simulation::new(Arc::new(scenario.model.clone()), scenario.config()).unwrap();
    for (step, want) in golden.iter().enumerate() {
        let row = sim.step().unwrap();
        assert_eq!(pyfmt::hex(&row.hash), *want, "households state hash differs from the recorded hash at step {step}");
    }
}

#[test]
fn an_early_election_matches_the_recorded_hashes() {
    // Stage S5.3: a general election in the second month, a hung parliament and a coalition.
    let scenario = load_scenario(&root().join("models/uk/scenarios/early_election.toml")).unwrap();
    let recorded = std::fs::read_to_string(root().join("models/uk/golden/early_election.hashes.csv")).unwrap();
    let golden: Vec<&str> = recorded.lines().skip(1).map(|line| line.split(',').nth(1).unwrap()).collect();
    assert_eq!(golden.len(), 3);
    let mut sim = Simulation::new(Arc::new(scenario.model.clone()), scenario.config()).unwrap();
    for (step, want) in golden.iter().enumerate() {
        let row = sim.step().unwrap();
        assert_eq!(
            pyfmt::hex(&row.hash),
            *want,
            "early election state hash differs from the recorded hash at step {step}"
        );
    }
}

#[test]
fn a_modded_uk_matches_the_recorded_hashes() {
    // Stage S7.1: the UK with the example mod (tests/mods/wealth_tax): an added lever, flow and
    // value, and two patched formulas, loaded the same way by both.
    let scenario = load_scenario(&root().join("models/uk/scenarios/wealth_tax.toml")).unwrap();
    assert_eq!(scenario.model.mods.len(), 1);
    let recorded = std::fs::read_to_string(root().join("models/uk/golden/wealth_tax.hashes.csv")).unwrap();
    let golden: Vec<&str> = recorded.lines().skip(1).map(|line| line.split(',').nth(1).unwrap()).collect();
    assert_eq!(golden.len(), 3);
    let mut sim = Simulation::new(Arc::new(scenario.model.clone()), scenario.config()).unwrap();
    for (step, want) in golden.iter().enumerate() {
        let row = sim.step().unwrap();
        assert_eq!(pyfmt::hex(&row.hash), *want, "modded UK state hash differs from the recorded hash at step {step}");
    }
}
