//! Save, load and continue must equal a run that was never interrupted.

use std::path::PathBuf;
use std::sync::Arc;

use polisim_core::{Error, Simulation, load_model, load_scenario};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

#[test]
fn resumed_run_equals_uninterrupted_run() {
    let mut scenario = load_scenario(&root().join("models/toy/scenarios/baseline.toml")).unwrap();
    // A policy change after the save point, so the resumed run must also pick up commands.
    scenario.commands.push((40, "basic_rate".to_string(), toml::Value::Float(0.23)));
    let model = Arc::new(scenario.model.clone());

    let mut straight = Simulation::new(Arc::clone(&model), scenario.config()).unwrap();
    let whole: Vec<_> = (0..60).map(|_| straight.step().unwrap()).collect();

    for save_at in [0usize, 1, 25, 39, 40, 59] {
        let mut first = Simulation::new(Arc::clone(&model), scenario.config()).unwrap();
        for expected in &whole[..save_at] {
            assert_eq!(&first.step().unwrap(), expected);
        }
        let bytes = first.save();
        drop(first);

        let mut second = Simulation::resume(Arc::clone(&model), &bytes).unwrap();
        second.set_commands(scenario.commands.clone());
        assert_eq!(second.steps_done(), save_at as u64);
        for expected in &whole[save_at..] {
            assert_eq!(&second.step().unwrap(), expected, "after saving at step {save_at}");
        }
        // Saving again straight after loading gives the same bytes.
        let reloaded = Simulation::resume(Arc::clone(&model), &bytes).unwrap();
        assert_eq!(reloaded.save(), bytes);
    }
}

#[test]
fn damaged_or_foreign_saves_are_refused() {
    let scenario = load_scenario(&root().join("models/toy/scenarios/baseline.toml")).unwrap();
    let model = Arc::new(scenario.model.clone());
    let mut sim = Simulation::new(Arc::clone(&model), scenario.config()).unwrap();
    sim.step().unwrap();
    let bytes = sim.save();

    let refused = |bytes: &[u8]| matches!(Simulation::resume(Arc::clone(&model), bytes), Err(Error::Model(_)));
    assert!(refused(&bytes[..bytes.len() - 1]), "cut short");
    assert!(refused(b"not a save"), "wrong file");
    let mut flipped = bytes.clone();
    let last = flipped.len() - 1;
    flipped[last] ^= 1; // one bit of the last stored value
    assert!(refused(&flipped), "a changed value must fail the hash check");
    let mut longer = bytes.clone();
    longer.push(0);
    assert!(refused(&longer), "trailing bytes");

    let other = Arc::new(load_model(&root().join("conformance/model")).unwrap());
    assert!(matches!(Simulation::resume(other, &bytes), Err(Error::Model(_))), "another model");
}

#[test]
fn a_dimensioned_model_resumes_exactly() {
    // Format 1: dimensioned parameters travel in the save as columns, states as columns.
    let mut scenario = load_scenario(&root().join("models/cohort/scenarios/base.toml")).unwrap();
    scenario.params.push(("local_rate".to_string(), toml::Value::Float(0.3)));
    let model = Arc::new(scenario.model.clone());
    let mut straight = Simulation::new(Arc::clone(&model), scenario.config()).unwrap();
    let whole: Vec<_> = (0..24).map(|_| straight.step().unwrap()).collect();

    let mut first = Simulation::new(Arc::clone(&model), scenario.config()).unwrap();
    for expected in &whole[..10] {
        assert_eq!(&first.step().unwrap(), expected);
    }
    let bytes = first.save();
    let mut second = Simulation::resume(Arc::clone(&model), &bytes).unwrap();
    for expected in &whole[10..] {
        assert_eq!(&second.step().unwrap(), expected);
    }
}
