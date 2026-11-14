//! Stage S7.3: situations. The shared cases in conformance/situation_cases.toml, which the
//! oracle runs too (oracle/tests/test_situations.py).

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use polisim_core::{RunConfig, Simulation, Val, load_model};
use toml::Value;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// The named values after each step.
fn run(model_text: &str, steps: usize, names: &[String]) -> polisim_core::Result<Vec<Vec<Option<Val>>>> {
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let n = NEXT.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::temp_dir().join(format!("polisim-situations-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("model.toml"), model_text).unwrap();
    let result = (|| {
        let model = Arc::new(load_model(&dir)?);
        let mut sim = Simulation::new(model, RunConfig::default())?;
        let mut after = Vec::new();
        for _ in 0..steps {
            sim.step()?;
            after.push(names.iter().map(|n| sim.scalar(n)).collect());
        }
        Ok(after)
    })();
    let _ = std::fs::remove_dir_all(&dir);
    result
}

fn same(got: Option<Val>, want: &Value) -> bool {
    match (got, want) {
        (Some(Val::I(a)), Value::Integer(b)) => a == *b,
        (Some(Val::F(a)), Value::Float(b)) => a == *b,
        (Some(Val::B(a)), Value::Boolean(b)) => a == *b,
        _ => false,
    }
}

#[test]
fn shared_cases_match_the_oracle() {
    let text = std::fs::read_to_string(root().join("conformance/situation_cases.toml")).unwrap();
    let cases: toml::Table = text.parse().unwrap();
    let base = cases["base"].as_str().unwrap();
    let list = cases["case"].as_array().unwrap();
    assert!(list.len() >= 10);
    for case in list {
        let case = case.as_table().unwrap();
        let name = case["name"].as_str().unwrap();
        let add = case["add"].as_str().unwrap().replace("\\n", "\n");
        let steps = case["steps"].as_integer().unwrap() as usize;
        let names: Vec<String> =
            case.get("series").and_then(Value::as_table).map(|s| s.keys().cloned().collect()).unwrap_or_default();
        let result = run(&format!("{base}\n{add}\n"), steps, &names);
        match case["expect"].as_str().unwrap() {
            "ran" => {
                let after = result.unwrap_or_else(|e| panic!("{name}: {e}"));
                for (i, (value, series)) in case["series"].as_table().unwrap().iter().enumerate() {
                    for (step, want) in series.as_array().unwrap().iter().enumerate() {
                        let got = after[step][i];
                        assert!(same(got, want), "{name}: {value} after step {step} is {got:?}, the oracle {want:?}");
                    }
                }
            }
            "refused" => assert!(result.is_err(), "{name}: the engine ran it"),
            other => panic!("{name}: unknown expectation {other}"),
        }
    }
}

#[test]
fn the_catalogue_marks_situations_good_or_bad() {
    let text = std::fs::read_to_string(root().join("conformance/situation_cases.toml")).unwrap();
    let cases: toml::Table = text.parse().unwrap();
    let base = cases["base"].as_str().unwrap();
    let dir = std::env::temp_dir().join(format!("polisim-situations-catalogue-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let add = "[situation.busy]\nlabel = \"Busy\"\ndoc = \"Things are busy\"\nstart = \"count > 1\"\n\n[situation.calm]\ngood = true\nstart = \"count > 3\"\n";
    std::fs::write(dir.join("model.toml"), format!("{base}\n{add}")).unwrap();
    let model = load_model(&dir).unwrap();
    let catalogue = polisim_core::Catalogue::of(&model);
    let entry = |n: &str| catalogue.entries.iter().find(|e| e.name == n).unwrap().clone();
    assert_eq!(entry("busy").situation, "bad");
    assert_eq!(entry("busy").label, "Busy");
    assert_eq!(entry("busy").doc, "Things are busy");
    assert_eq!(entry("calm").situation, "good");
    assert_eq!(entry("count").situation, "");
    let _ = std::fs::remove_dir_all(dir);
}
