//! Stage S10: the engine computes records, cells, aggregates and independent formulas on
//! several threads. A run must give the same state hash on every step whatever the number
//! of threads: here one, two and eight, on the UK (households, voters, dilemmas) and the
//! cohort model (dimensions).

use std::path::PathBuf;
use std::sync::Arc;

use polisim_core::{Simulation, load_scenario};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn hashes(scenario: &str, steps: usize, threads: usize) -> Vec<[u8; 32]> {
    let scenario = load_scenario(&root().join(scenario)).unwrap();
    let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build().unwrap();
    pool.install(|| {
        let mut sim = Simulation::new(Arc::new(scenario.model.clone()), scenario.config()).unwrap();
        (0..steps).map(|_| sim.step().unwrap().hash).collect()
    })
}

#[test]
fn the_uk_is_the_same_on_one_two_and_eight_threads() {
    let one = hashes("models/uk/scenarios/2025.toml", 8, 1);
    assert_eq!(hashes("models/uk/scenarios/2025.toml", 8, 2), one);
    assert_eq!(hashes("models/uk/scenarios/2025.toml", 8, 8), one);
}

#[test]
fn the_cohort_model_is_the_same_on_one_and_eight_threads() {
    let one = hashes("models/cohort/scenarios/base.toml", 24, 1);
    assert_eq!(hashes("models/cohort/scenarios/base.toml", 24, 8), one);
}

/// When several formulas fail in one step, the error is the one plan order meets first,
/// even when a level's formulas ran together: here y (which reads x) and z both divide by
/// zero, y comes first in plan order but z is in the earlier level.
#[test]
fn a_failure_is_the_one_plan_order_meets_first() {
    let model = r#"
[model]
id = "failures"
format = 1
currency = "GBP"
minor_units = 100
step = "month"
phases = ["one"]

[dim.d]
range = [0, 99]

[state.count]
type = "int"
unit = "1"
phase = "one"
initial = 0
next = "count + 1"

[var.x]
type = "real"
unit = "1"
phase = "one"
dims = ["d"]
expr = "1.0 * coord(d)"

[var.y]
type = "real"
unit = "1"
phase = "one"
dims = ["d"]
expr = "x / select(count >= 1, 0.0, 1.0)"

[var.z]
type = "real"
unit = "1"
phase = "one"
dims = ["d"]
expr = "1.0 / select(count >= 1, 0.0, 1.0)"
"#;
    let dir = std::env::temp_dir().join(format!("polisim-failures-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("model.toml"), model).unwrap();
    let loaded = Arc::new(polisim_core::load_model(&dir).unwrap());
    let _ = std::fs::remove_dir_all(&dir);
    for threads in [1, 4] {
        let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build().unwrap();
        let error = pool.install(|| {
            let mut sim = Simulation::new(Arc::clone(&loaded), polisim_core::RunConfig::default()).unwrap();
            sim.step().unwrap();
            sim.step().unwrap_err().to_string()
        });
        assert!(error.contains("var y"), "{threads} threads: {error}");
    }
}
