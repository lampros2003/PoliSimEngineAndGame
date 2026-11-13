//! The engine must reproduce the state hashes the Python oracle recorded for the toy
//! model's baseline, on every step.

use std::path::PathBuf;
use std::sync::Arc;

use polisim_core::{Simulation, load_scenario, pyfmt};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

#[test]
fn baseline_matches_the_oracles_recorded_hashes() {
    let scenario = load_scenario(&root().join("models/toy/scenarios/baseline.toml")).unwrap();
    let recorded = std::fs::read_to_string(root().join("models/toy/golden/baseline.hashes.csv")).unwrap();
    let golden: Vec<&str> = recorded.lines().skip(1).map(|line| line.split(',').nth(1).unwrap()).collect();
    assert_eq!(golden.len(), 240);

    let mut sim = Simulation::new(Arc::new(scenario.model.clone()), scenario.config()).unwrap();
    for (step, want) in golden.iter().enumerate() {
        let row = sim.step().unwrap();
        assert_eq!(row.step, step as u64);
        assert_eq!(pyfmt::hex(&row.hash), *want, "state hash differs from the oracle at step {step}");
    }
}
