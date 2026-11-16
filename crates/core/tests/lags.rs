//! Stage S10.5: lags. The shared cases in conformance/lag_cases.toml, with their recorded
//! outcomes, a save in the middle of a lag, and the catalogue.

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use polisim_core::model::Kind;
use polisim_core::{Catalogue, RunConfig, Simulation, Val, load_model};
use toml::Value;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn folder(model_text: &str) -> PathBuf {
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let n = NEXT.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::temp_dir().join(format!("polisim-lags-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("model.toml"), model_text).unwrap();
    dir
}

enum Outcome {
    Refused(String),
    Runtime(usize, String),
    Ran(Vec<Vec<Option<Val>>>),
}

fn run(model_text: &str, commands: Vec<(u64, String, Value)>, steps: usize, names: &[String]) -> Outcome {
    let dir = folder(model_text);
    let outcome = (|| {
        let model = match load_model(&dir) {
            Ok(m) => Arc::new(m),
            Err(e) => return Outcome::Refused(e.to_string()),
        };
        let mut sim = match Simulation::new(model, RunConfig::default()) {
            Ok(s) => s,
            Err(e) => return Outcome::Refused(e.to_string()),
        };
        sim.set_commands(commands);
        let mut after = Vec::new();
        for step in 0..steps {
            if let Err(e) = sim.step() {
                return Outcome::Runtime(step, e.to_string());
            }
            after.push(names.iter().map(|n| sim.scalar(n)).collect());
        }
        Outcome::Ran(after)
    })();
    let _ = std::fs::remove_dir_all(&dir);
    outcome
}

fn same(got: Option<Val>, want: &Value) -> bool {
    match (got, want) {
        (Some(Val::I(a)), Value::Integer(b)) => a == *b,
        (Some(Val::F(a)), Value::Float(b)) => a == *b,
        (Some(Val::B(a)), Value::Boolean(b)) => a == *b,
        _ => false,
    }
}

fn cases() -> toml::Table {
    std::fs::read_to_string(root().join("conformance/lag_cases.toml")).unwrap().parse().unwrap()
}

#[test]
fn shared_cases_match_their_recorded_outcomes() {
    let cases = cases();
    let base = cases["base"].as_str().unwrap();
    let list = cases["case"].as_array().unwrap();
    assert!(list.len() >= 25);
    for case in list {
        let case = case.as_table().unwrap();
        let name = case["name"].as_str().unwrap();
        let add = case["add"].as_str().unwrap().replace("\\n", "\n");
        let steps = case["steps"].as_integer().unwrap() as usize;
        let commands: Vec<(u64, String, Value)> = case
            .get("commands")
            .and_then(Value::as_array)
            .map(|list| {
                list.iter()
                    .map(|c| {
                        let c = c.as_array().unwrap();
                        (c[0].as_integer().unwrap() as u64, c[1].as_str().unwrap().to_string(), c[2].clone())
                    })
                    .collect()
            })
            .unwrap_or_default();
        let names: Vec<String> =
            case.get("series").and_then(Value::as_table).map(|s| s.keys().cloned().collect()).unwrap_or_default();
        let outcome = run(&format!("{base}\n{add}\n"), commands, steps, &names);
        match (case["expect"].as_str().unwrap(), outcome) {
            ("ran", Outcome::Ran(after)) => {
                for (i, (value, series)) in case["series"].as_table().unwrap().iter().enumerate() {
                    for (step, want) in series.as_array().unwrap().iter().enumerate() {
                        let got = after[step][i];
                        assert!(same(got, want), "{name}: {value} after step {step} is {got:?}, recorded {want:?}");
                    }
                }
            }
            ("refused", Outcome::Refused(_)) => {}
            ("runtime", Outcome::Runtime(step, e)) => {
                assert_eq!(step as i64, case["at"].as_integer().unwrap(), "{name}: failed at step {step}: {e}")
            }
            (want, Outcome::Ran(_)) => panic!("{name}: expected {want}, the engine ran it"),
            (want, Outcome::Refused(e)) => panic!("{name}: expected {want}, the engine refused it: {e}"),
            (want, Outcome::Runtime(step, e)) => panic!("{name}: expected {want}, step {step} failed: {e}"),
        }
    }
}

const ADD: &str =
    "[lag.back]\nlabel = \"Back\"\nof = \"count\"\nsteps = 3\n\n[lag.rate_back]\nof = \"rate\"\nsteps = 2";

#[test]
fn a_save_in_the_middle_of_a_lag_resumes_the_same_run() {
    let dir = folder(&format!("{}\n{ADD}\n", cases()["base"].as_str().unwrap()));
    let model = Arc::new(load_model(&dir).unwrap());
    let _ = std::fs::remove_dir_all(&dir);
    let commands = vec![(1, "rate".to_string(), Value::Float(0.75))];
    let mut straight = Simulation::new(Arc::clone(&model), RunConfig::default()).unwrap();
    straight.set_commands(commands.clone());
    let mut hashes = Vec::new();
    let mut backs = Vec::new();
    for _ in 0..7 {
        straight.step().unwrap();
        hashes.push(straight.state_hash());
        backs.push((straight.scalar("back"), straight.scalar("rate_back")));
    }
    assert_eq!(backs[4], (Some(Val::I(2)), Some(Val::F(0.75))));
    let mut first = Simulation::new(Arc::clone(&model), RunConfig::default()).unwrap();
    first.set_commands(commands);
    for _ in 0..2 {
        first.step().unwrap();
    }
    let bytes = first.save();
    let mut resumed = Simulation::resume(Arc::clone(&model), &bytes).unwrap();
    for (hash, back) in hashes[2..].iter().zip(&backs[2..]) {
        resumed.step().unwrap();
        assert_eq!(resumed.state_hash(), *hash);
        assert_eq!((resumed.scalar("back"), resumed.scalar("rate_back")), *back);
    }
}

#[test]
fn the_catalogue_links_a_lag_to_what_it_follows() {
    let dir = folder(&format!("{}\n{ADD}\n", cases()["base"].as_str().unwrap()));
    let model = load_model(&dir).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    let sim = Simulation::new(Arc::new(model.clone()), RunConfig::default()).unwrap();
    let mut catalogue = Catalogue::of(&model);
    let (deps, lagged) = sim.dependencies();
    catalogue.link(&model, deps, lagged);
    let back = catalogue.entry("back").unwrap();
    assert_eq!((back.kind, back.label.as_str(), back.lag.as_str()), (Kind::Var, "Back", "back"));
    assert!(back.inputs.is_empty());
    assert_eq!(back.lagged_inputs, ["count"]);
    for state in ["back__1", "back__2", "back__3"] {
        let entry = catalogue.entry(state).unwrap();
        assert_eq!((entry.kind, entry.lag.as_str()), (Kind::State, "back"));
        assert!(entry.inputs.is_empty() && entry.lagged_inputs.is_empty(), "{state}");
    }
    assert_eq!(catalogue.entry("rate_back").unwrap().lagged_inputs, ["rate"]);
    assert_eq!(catalogue.entry("count").unwrap().lag, "");
}
