//! Stage S7.1: mods. The shared cases in conformance/mod_cases.toml, which the oracle runs
//! too (oracle/tests/test_mods.py): the same outcome, the same values and the same model
//! hash on both sides.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use polisim_core::{Model, RunConfig, Session, Simulation, Val, load_model_with_mods, pyfmt};
use toml::Value;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn folder(name: &str) -> PathBuf {
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let n = NEXT.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::temp_dir().join(format!("polisim-mods-{}-{n}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn text(value: &Value) -> String {
    value.as_str().unwrap().replace("\\n", "\n")
}

/// Writes the case's model and mods; returns the model folder and the mod folders.
fn write_case(base: &str, case: &toml::Table, dir: &Path) -> (PathBuf, Vec<PathBuf>) {
    let model = dir.join("model");
    std::fs::create_dir_all(&model).unwrap();
    std::fs::write(model.join("model.toml"), base).unwrap();
    let mut mods = Vec::new();
    for (i, m) in case.get("mods").and_then(Value::as_array).into_iter().flatten().enumerate() {
        let m = m.as_table().unwrap();
        let at = dir.join(format!("mod{i}"));
        std::fs::create_dir_all(&at).unwrap();
        std::fs::write(at.join("mod.toml"), text(&m["toml"])).unwrap();
        for (name, content) in m.get("files").and_then(Value::as_table).into_iter().flatten() {
            std::fs::write(at.join(name), text(content)).unwrap();
        }
        mods.push(at);
    }
    (model, mods)
}

fn run(model: &Path, mods: &[PathBuf]) -> polisim_core::Result<(Model, Simulation)> {
    let model = load_model_with_mods(model, mods)?;
    let shared = Arc::new(model.clone());
    let mut sim = Simulation::new(shared, RunConfig::default())?;
    sim.step()?;
    Ok((model, sim))
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
    let file = std::fs::read_to_string(root().join("conformance/mod_cases.toml")).unwrap();
    let cases: toml::Table = file.parse().unwrap();
    let base = cases["base"].as_str().unwrap();
    let list = cases["case"].as_array().unwrap();
    assert!(list.len() >= 15);
    for case in list {
        let case = case.as_table().unwrap();
        let name = case["name"].as_str().unwrap();
        let dir = folder("case");
        let (model, mods) = write_case(base, case, &dir);
        let result = run(&model, &mods);
        match case["expect"].as_str().unwrap() {
            "ran" => {
                let (model, sim) = result.unwrap_or_else(|e| panic!("{name}: {e}"));
                for (value, want) in case["values"].as_table().unwrap() {
                    assert!(
                        same(sim.scalar(value), want),
                        "{name}: {value} is {:?}, the oracle {want:?}",
                        sim.scalar(value)
                    );
                }
                assert_eq!(model.mod_notes.len() as i64, case["notes"].as_integer().unwrap(), "{name}: notes");
                assert_eq!(pyfmt::hex(&model.model_hash), case["model_hash"].as_str().unwrap(), "{name}: model hash");
            }
            "refused" => assert!(result.is_err(), "{name}: the engine loaded it"),
            other => panic!("{name}: unknown expectation {other}"),
        }
        let _ = std::fs::remove_dir_all(dir);
    }
}

#[test]
fn a_scenario_lists_its_mods_and_a_session_reloads_them() {
    let file = std::fs::read_to_string(root().join("conformance/mod_cases.toml")).unwrap();
    let cases: toml::Table = file.parse().unwrap();
    let case = cases["case"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c.as_table().unwrap())
        .find(|c| c["name"].as_str() == Some("a mod that adds a lever and a value"))
        .unwrap();
    let dir = folder("scenario");
    let (_, mods) = write_case(cases["base"].as_str().unwrap(), case, &dir);
    std::fs::rename(&mods[0], dir.join("extra")).unwrap();
    std::fs::write(dir.join("game.toml"), "[scenario]\nmodel = \"model\"\nseed = 1\nsteps = 3\nmods = [\"extra\"]\n")
        .unwrap();
    let mut session = Session::open(&dir.join("game.toml")).unwrap();
    assert_eq!(session.model().mods.len(), 1);
    assert_eq!(session.model().mods[0].name, "An extra levy");
    session.step().unwrap();
    assert_eq!(session.latest("extra_total"), Some(Val::F(25.0)));
    // Reloading reads the mod again: a change to it takes effect.
    let file = dir.join("extra").join("extra.toml");
    let changed = std::fs::read_to_string(&file).unwrap().replace("default = 0.05", "default = 0.05\n");
    std::fs::write(&file, changed.replace("revenue + extra_levy * scale", "revenue + 2.0 * extra_levy * scale"))
        .unwrap();
    session.reload().unwrap();
    session.step().unwrap();
    assert_eq!(session.latest("extra_total"), Some(Val::F(30.0)));
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn a_saved_game_keeps_the_mods_the_player_chose() {
    let file = std::fs::read_to_string(root().join("conformance/mod_cases.toml")).unwrap();
    let cases: toml::Table = file.parse().unwrap();
    let case = cases["case"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c.as_table().unwrap())
        .find(|c| c["name"].as_str() == Some("a mod that adds a lever and a value"))
        .unwrap();
    let dir = folder("chosen");
    let (_, mods) = write_case(cases["base"].as_str().unwrap(), case, &dir);
    std::fs::write(dir.join("game.toml"), "[scenario]\nmodel = \"model\"\nseed = 1\nsteps = 3\n").unwrap();
    let path = dir.join("game.toml");

    let mut session = Session::open_with_mods(&path, &mods).unwrap();
    session.step().unwrap();
    let bytes = session.save();
    let loaded = Session::load(&path, &bytes).unwrap();
    assert_eq!(loaded.extra_mods(), mods.as_slice());
    assert!(loaded.migration().is_none(), "the same model, mods included");
    assert_eq!(loaded.latest("extra_total"), Some(Val::F(25.0)));

    // Without the mod, the game carries on without its values.
    std::fs::rename(&mods[0], dir.join("moved")).unwrap();
    let mut loaded = Session::load(&path, &bytes).unwrap();
    assert_eq!(loaded.missing_mods().len(), 1);
    let migration = loaded.migration().expect("the model changed");
    assert!(migration.dropped.contains(&"extra_levy".to_string()), "{migration:?}");
    assert_eq!(loaded.latest("extra_total"), None);
    loaded.step().unwrap();
    let _ = std::fs::remove_dir_all(dir);
}
