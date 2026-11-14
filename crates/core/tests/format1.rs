//! Model format 1 (docs/spec/06-model-format-1.md): the engine refuses the same bad
//! declarations and data files as the oracle (oracle/tests/test_format1.py).

use std::path::PathBuf;

use polisim_core::{RunConfig, Simulation, load_model};

const HEAD: &str = r#"
[model]
id = "t"
format = 1
currency = "GBP"
minor_units = 100
step = "month"
phases = ["one"]

[dim.age]
range = [10, 13]

[dim.sex]
members = ["female", "male"]
"#;

const RATE: &str = r#"
[param.rate]
type = "real"
unit = "1"
dims = ["sex", "age"]
data = "rates.csv"
"#;

fn folder(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("polisim-format1-{}-{name}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// Loads and starts a model; true if both succeed.
fn loads(name: &str, model: &str, files: &[(&str, String)]) -> bool {
    let dir = folder(name);
    std::fs::write(dir.join("model.toml"), model).unwrap();
    for (file, text) in files {
        std::fs::write(dir.join(file), text).unwrap();
    }
    let ok = load_model(&dir)
        .and_then(|m| Simulation::new(std::sync::Arc::new(m), RunConfig::default()).map(|_| ()))
        .is_ok();
    std::fs::remove_dir_all(&dir).ok();
    ok
}

#[test]
fn bad_declarations_are_refused() {
    let var = |dims: &str| {
        format!("[var.x]\ntype = \"real\"\nunit = \"1\"\nphase = \"one\"\ndims = {dims}\nexpr = \"1.0\"\n")
    };
    let cases = [
        ("format0", HEAD.replace("format = 1", "format = 0")),
        ("unknown", format!("{HEAD}{}", var("[\"height\"]"))),
        ("repeated", format!("{HEAD}{}", var("[\"age\", \"age\"]"))),
        ("lever", format!("{HEAD}[lever.x]\ntype = \"real\"\nunit = \"1\"\ndefault = 1.0\ndims = [\"age\"]\n")),
        ("member", format!("{HEAD}[param.female]\ntype = \"real\"\nunit = \"1\"\nvalue = 1.0\n")),
        ("emptyrange", HEAD.replace("range = [10, 13]", "range = [13, 10]")),
        ("both", HEAD.replace("range = [10, 13]", "range = [10, 13]\nmembers = [\"a\"]")),
    ];
    assert!(loads("good", &format!("{HEAD}{}", var("[\"sex\", \"age\"]")), &[]));
    for (name, model) in cases {
        assert!(!loads(name, &model, &[]), "{name} should be refused");
    }
}

#[test]
fn a_data_file_must_hold_every_cell_once() {
    let full: String = std::iter::once("sex,age,value\n".to_string())
        .chain(["female", "male"].iter().flat_map(|s| (10..14).map(move |a| format!("{s},{a},0.1\n"))))
        .collect();
    let model = format!("{HEAD}{RATE}");
    assert!(loads("full", &model, &[("rates.csv", full.clone())]));
    let cases = [
        ("missing", full.replace("male,13,0.1\n", "")),
        ("twice", format!("{full}male,13,0.2\n")),
        ("unknown", full.replace("male,13", "male,14")),
        ("nocolumn", full.replace("value", "rate")),
    ];
    for (name, text) in cases {
        assert!(!loads(name, &model, &[("rates.csv", text)]), "{name} should be refused");
    }
}

#[test]
fn reserved_function_names_match_the_oracle() {
    // The oracle reserves the name of every function it implements
    // (oracle/polisim_oracle/expr.py, FUNCTIONS); a model may not name an element after one.
    let oracle =
        std::fs::read_to_string(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../oracle/polisim_oracle/expr.py"))
            .unwrap();
    let mut names: Vec<&str> =
        oracle.lines().filter_map(|l| l.trim().strip_prefix("def _fn_")).filter_map(|l| l.split('(').next()).collect();
    names.sort();
    assert_eq!(names, polisim_core::model::FUNCTIONS.to_vec());
}

/// Reloading unchanged files carries dimensioned states across: the run goes on exactly as
/// if it had never been reloaded (before S4.4 they started again from their initial value).
#[test]
fn an_unchanged_reload_keeps_dimensioned_states() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let scenario = polisim_core::load_scenario(&root.join("models/cohort/scenarios/base.toml")).unwrap();
    let model = std::sync::Arc::new(scenario.model.clone());
    let mut plain = Simulation::new(std::sync::Arc::clone(&model), scenario.config()).unwrap();
    let mut sim = Simulation::new(std::sync::Arc::clone(&model), scenario.config()).unwrap();
    for _ in 0..5 {
        plain.step().unwrap();
        sim.step().unwrap();
    }
    let (mut reloaded, reset) = sim.reload(std::sync::Arc::clone(&model), &scenario.preset, Vec::new()).unwrap();
    assert!(reset.is_empty(), "{reset:?}");
    for _ in 0..5 {
        assert_eq!(reloaded.step().unwrap().hash, plain.step().unwrap().hash);
    }
}
