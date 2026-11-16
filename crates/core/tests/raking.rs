//! Weights that change (docs/spec/06-model-format-1.md, stage S4.4): the cases in
//! conformance/rake_cases.toml, with their recorded outcomes,
//! and the test model models/raking through saves, explanations and a reload.

use std::path::PathBuf;
use std::sync::Arc;

use polisim_core::{Col, Computed, Error, Num, RunConfig, Simulation, Ty, Val, load_model, load_scenario, pyfmt};
use toml::Value;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

enum Outcome {
    Refused(String),
    Runtime(String),
    Weights(Vec<i64>),
}

fn outcome(cases: &toml::Table, case: &toml::Table, index: usize) -> Outcome {
    let mut text = cases["base"].as_str().unwrap().to_string();
    for pair in case.get("replace").and_then(Value::as_array).into_iter().flatten() {
        let pair = pair.as_array().unwrap();
        let old = pair[0].as_str().unwrap().replace("\\n", "\n");
        let new = pair[1].as_str().unwrap().replace("\\n", "\n");
        assert_eq!(text.matches(&old).count(), 1, "{old:?}");
        text = text.replace(&old, &new);
    }
    let dir = std::env::temp_dir().join(format!("polisim-raking-{}-{index}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("model.toml"), text).unwrap();
    let mut files = cases["files"].as_table().unwrap().clone();
    if let Some(extra) = case.get("files").and_then(Value::as_table) {
        files.extend(extra.clone());
    }
    for (name, content) in &files {
        std::fs::write(dir.join(name), content.as_str().unwrap()).unwrap();
    }
    let result = (|| {
        let model = match load_model(&dir) {
            Ok(m) => m,
            Err(e) => return Outcome::Refused(e.to_string()),
        };
        let mut sim = match Simulation::new(Arc::new(model), RunConfig::default()) {
            Ok(s) => s,
            Err(e) => return Outcome::Refused(e.to_string()),
        };
        if let Err(e) = sim.step() {
            return Outcome::Runtime(e.to_string());
        }
        match sim.column("w") {
            Some(Col::I(w)) => Outcome::Weights(w.clone()),
            _ => panic!("the weights are whole numbers"),
        }
    })();
    std::fs::remove_dir_all(&dir).ok();
    result
}

#[test]
fn shared_cases_match_their_expectations() {
    let text = std::fs::read_to_string(root().join("conformance/rake_cases.toml")).unwrap();
    let cases: toml::Table = text.parse().unwrap();
    let list = cases["case"].as_array().unwrap();
    assert!(list.len() >= 30);
    for (index, case) in list.iter().enumerate() {
        let case = case.as_table().unwrap();
        let name = case["name"].as_str().unwrap();
        let expect = case["expect"].as_str().unwrap();
        match (outcome(&cases, case, index), expect) {
            (Outcome::Weights(got), "weights") => {
                let want: Vec<i64> =
                    case["weights"].as_array().unwrap().iter().map(|v| v.as_integer().unwrap()).collect();
                assert_eq!(got, want, "{name}");
            }
            (Outcome::Refused(_), "refused") | (Outcome::Runtime(_), "runtime") => {}
            (Outcome::Refused(e), _) => panic!("{name}: refused ({e}), expected {expect}"),
            (Outcome::Runtime(e), _) => panic!("{name}: failed at run time ({e}), expected {expect}"),
            (Outcome::Weights(w), _) => panic!("{name}: gave weights {w:?}, expected {expect}"),
        }
    }
}

fn raking() -> (Arc<polisim_core::Model>, RunConfig) {
    let scenario = load_scenario(&root().join("models/raking/scenarios/base.toml")).unwrap();
    (Arc::new(scenario.model.clone()), scenario.config())
}

fn golden() -> Vec<String> {
    let recorded = std::fs::read_to_string(root().join("models/raking/golden/base.hashes.csv")).unwrap();
    recorded.lines().skip(1).map(|line| line.split(',').nth(1).unwrap().to_string()).collect()
}

#[test]
fn the_test_model_matches_the_recorded_hashes() {
    let golden = golden();
    assert_eq!(golden.len(), 36);
    let (model, config) = raking();
    let mut sim = Simulation::new(model, config).unwrap();
    for (step, want) in golden.iter().enumerate() {
        let row = sim.step().unwrap();
        assert_eq!(pyfmt::hex(&row.hash), *want, "raking state hash differs from the recorded hash at step {step}");
    }
}

#[test]
fn a_saved_run_resumes_across_a_rake() {
    let golden = golden();
    let (model, config) = raking();
    let mut sim = Simulation::new(Arc::clone(&model), config).unwrap();
    for _ in 0..7 {
        sim.step().unwrap();
    }
    let mut resumed = Simulation::resume(Arc::clone(&model), &sim.save()).unwrap();
    for (step, want) in golden.iter().enumerate().skip(7) {
        let row = resumed.step().unwrap();
        assert_eq!(pyfmt::hex(&row.hash), *want, "resumed run differs at step {step}");
    }
}

#[test]
fn an_unchanged_reload_keeps_the_run() {
    let golden = golden();
    let (model, config) = raking();
    let mut sim = Simulation::new(Arc::clone(&model), config).unwrap();
    for _ in 0..12 {
        sim.step().unwrap();
    }
    let (mut reloaded, reset) = sim.reload(Arc::clone(&model), "central", Vec::new()).unwrap();
    assert!(reset.is_empty(), "{reset:?}");
    for (step, want) in golden.iter().enumerate().skip(12) {
        let row = reloaded.step().unwrap();
        assert_eq!(pyfmt::hex(&row.hash), *want, "reloaded run differs at step {step}");
    }
}

#[test]
fn values_are_explained_across_a_rake() {
    let (model, config) = raking();
    let mut sim = Simulation::new(model, config).unwrap();
    sim.set_tracing(true);
    for _ in 0..13 {
        sim.step().unwrap();
    }
    // Step 12 raked the weights: a total after the rake changes, one before it does not.
    let after = sim.explain("households").unwrap();
    assert!(!after.change.is_zero());
    let before = sim.explain("households_before").unwrap();
    assert!(before.change.is_zero());
    let heavy = sim.explain("heavy_households");
    assert!(heavy.is_ok(), "{heavy:?}");
    let weights = sim.explain("household_weight").unwrap();
    assert!(weights.note.is_some_and(|n| n.contains("raking")));
    assert!(matches!(weights.change, Num::Int(c) if c != 0));
}

#[test]
fn a_failed_step_puts_the_weights_back() {
    // The base of the shared cases, with a check in the phase after the rake that fails.
    let text = std::fs::read_to_string(root().join("conformance/rake_cases.toml")).unwrap();
    let cases: toml::Table = text.parse().unwrap();
    let model = cases["base"].as_str().unwrap().to_string()
        + "\n[var.check]\ntype = \"real\"\nunit = \"1\"\nphase = \"two\"\nrange = [2.0, 3.0]\nexpr = \"1.0\"\n";
    let dir = std::env::temp_dir().join(format!("polisim-raking-rollback-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("model.toml"), model).unwrap();
    for (name, content) in cases["files"].as_table().unwrap() {
        std::fs::write(dir.join(name), content.as_str().unwrap()).unwrap();
    }
    let mut sim = Simulation::new(Arc::new(load_model(&dir).unwrap()), RunConfig::default()).unwrap();
    std::fs::remove_dir_all(&dir).ok();
    sim.set_tracing(true);
    let total = |sim: &Simulation| sim.evaluate("wcount(hh, true)", None, Ty::Int, "hh").unwrap();
    assert_eq!(total(&sim), Computed::One(Val::I(100)));
    assert!(matches!(sim.step(), Err(Error::Sim(_))));
    assert!(sim.roll_back());
    assert_eq!(sim.column("w"), Some(&Col::I(vec![10, 20, 30, 40])));
    assert_eq!(total(&sim), Computed::One(Val::I(100)));
}
