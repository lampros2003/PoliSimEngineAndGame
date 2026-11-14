//! Stage S7.0: saves that follow the model when its files change.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use polisim_core::{Error, Migration, Session, Simulation, Val, load_model, load_scenario};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// A copy of a model folder (with its data and scenarios) that a test may change.
fn copy_model(from: &Path, name: &str) -> PathBuf {
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let n = NEXT.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::temp_dir().join(format!("polisim-migration-{}-{n}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    copy_dir(from, &dir);
    dir
}

fn copy_dir(from: &Path, to: &Path) {
    std::fs::create_dir_all(to).unwrap();
    for entry in std::fs::read_dir(from).unwrap() {
        let entry = entry.unwrap();
        let target = to.join(entry.file_name());
        if entry.file_type().unwrap().is_dir() {
            copy_dir(&entry.path(), &target);
        } else {
            std::fs::copy(entry.path(), target).unwrap();
        }
    }
}

fn edit(file: &Path, change: impl Fn(String) -> String) {
    let text = std::fs::read_to_string(file).unwrap();
    std::fs::write(file, change(text)).unwrap();
}

const OLD_COUNTER: &str = "
[state.old_counter]
label = \"A count the next version drops\"
type = \"int\"
unit = \"1\"
phase = \"labour\"
initial = 0
next = \"old_counter + 1\"
";

const MONTHS_RUN: &str = "
[state.months_run]
label = \"A count the next version adds\"
type = \"int\"
unit = \"1\"
phase = \"labour\"
initial = 0
next = \"months_run + 1\"
";

/// The toy model's next version: `employed` is now `in_work`, `old_counter` is gone,
/// `months_run` is new and the basic rate may not go above 22%.
fn next_version(dir: &Path) {
    edit(&dir.join("economy.toml"), |text| {
        let text = text.replace(OLD_COUNTER, "");
        let mut out = String::new();
        // Whole words only: `unemployed` and the column `employed0` stay.
        let bytes = text.as_bytes();
        let word = |b: u8| b.is_ascii_alphanumeric() || b == b'_';
        let mut i = 0;
        while i < bytes.len() {
            let rest = &text[i..];
            let before_ok = i == 0 || !word(bytes[i - 1]);
            let after = i + "employed".len();
            if before_ok && rest.starts_with("employed") && (after >= bytes.len() || !word(bytes[after])) {
                out.push_str("in_work");
                i = after;
            } else {
                let c = rest.chars().next().unwrap();
                out.push(c);
                i += c.len_utf8();
            }
        }
        out.replace(
            "default = 0.20\nrange = [0, 1]\ndoc = \"Income tax rate between the allowance and the higher threshold\"",
            "default = 0.20\nrange = [0, 0.22]\ndoc = \"Income tax rate between the allowance and the higher threshold\"",
        ) + MONTHS_RUN
    });
    edit(&dir.join("model.toml"), |text| text + "\n[renamed]\nemployed = \"in_work\"\n");
}

#[test]
fn a_save_follows_a_rename_an_addition_a_removal_and_a_new_range() {
    let dir = copy_model(&root().join("models/toy"), "toy");
    edit(&dir.join("economy.toml"), |text| text + OLD_COUNTER);
    let mut scenario = load_scenario(&dir.join("scenarios/baseline.toml")).unwrap();
    scenario.commands.push((3, "basic_rate".to_string(), toml::Value::Float(0.23)));
    let model = Arc::new(scenario.model.clone());
    let mut sim = Simulation::new(Arc::clone(&model), scenario.config()).unwrap();
    for _ in 0..12 {
        sim.step().unwrap();
    }
    let bytes = sim.save();
    let employed = sim.column("employed").unwrap().clone();
    let money = sim.scalar("hh_money.total");

    next_version(&dir);
    let scenario = load_scenario(&dir.join("scenarios/baseline.toml")).unwrap();
    let changed = Arc::new(scenario.model.clone());
    assert_ne!(changed.model_hash, model.model_hash);
    // The exact loader still refuses it.
    assert!(matches!(Simulation::resume(Arc::clone(&changed), &bytes), Err(Error::Model(_))));

    let (mut moved, migration) =
        Simulation::migrate(Arc::clone(&changed), &bytes, &scenario.preset, scenario.params.clone()).unwrap();
    let migration = migration.expect("the model changed");
    assert_eq!(migration.renamed, vec![("employed".to_string(), "in_work".to_string())]);
    assert_eq!(migration.reset, vec!["months_run".to_string()]);
    assert_eq!(migration.clamped, vec!["basic_rate".to_string()]);
    assert_eq!(migration.dropped, vec!["old_counter".to_string()]);
    assert_eq!(moved.steps_done(), 12);
    assert_eq!(moved.column("in_work"), Some(&employed));
    assert_eq!(moved.scalar("basic_rate"), Some(Val::F(0.22)));
    assert_eq!(moved.scalar("months_run"), Some(Val::I(0)));
    assert_eq!(moved.scalar("hh_money.total"), money);
    for _ in 0..12 {
        moved.step().unwrap();
    }
    assert_eq!(moved.scalar("months_run"), Some(Val::I(12)));

    // A save of the migrated run belongs to the new model and loads exactly.
    let again = moved.save();
    let resumed = Simulation::resume(Arc::clone(&changed), &again).unwrap();
    assert_eq!(resumed.state_hash(), moved.state_hash());
    let _ = std::fs::remove_dir_all(dir);
}

#[test]
fn an_unchanged_model_loads_exactly_and_reports_nothing() {
    let scenario = load_scenario(&root().join("models/cohort/scenarios/base.toml")).unwrap();
    let model = Arc::new(scenario.model.clone());
    let mut sim = Simulation::new(Arc::clone(&model), scenario.config()).unwrap();
    for _ in 0..5 {
        sim.step().unwrap();
    }
    let bytes = sim.save();
    let (resumed, migration) = Simulation::migrate(model, &bytes, "central", Vec::new()).unwrap();
    assert_eq!(migration, None);
    assert_eq!(resumed.save(), bytes);
}

#[test]
fn a_dimension_with_new_members_starts_again() {
    // Format 1: a value is carried only when its dimensions keep their members.
    let dir = copy_model(&root().join("models/cohort"), "cohort");
    let scenario = load_scenario(&dir.join("scenarios/base.toml")).unwrap();
    let model = Arc::new(scenario.model.clone());
    let mut sim = Simulation::new(Arc::clone(&model), scenario.config()).unwrap();
    for _ in 0..3 {
        sim.step().unwrap();
    }
    let bytes = sim.save();
    let renamed_region = model.dims.iter().find(|d| d.first.is_none()).expect("a listed dimension").clone();
    let first = renamed_region.members[0].clone();
    // Rename a member everywhere it is written: model files and data.
    for file in walk(&dir) {
        if file.extension().is_some_and(|e| e == "toml" || e == "csv") {
            edit(&file, |text| replace_word(&text, &first, "renamed_member"));
        }
    }
    let changed = Arc::new(load_model(&dir).unwrap());
    let (_, migration) = Simulation::migrate(Arc::clone(&changed), &bytes, "central", Vec::new()).unwrap();
    let migration: Migration = migration.unwrap();
    let by_dim: Vec<&str> = changed
        .symbols
        .iter()
        .filter(|d| d.dims.iter().any(|&i| changed.dims[i].name == renamed_region.name))
        .map(|d| d.name.as_str())
        .collect();
    assert!(!migration.reset.is_empty());
    assert!(migration.reset.iter().all(|name| by_dim.contains(&name.as_str())), "{:?}", migration.reset);
    let _ = std::fs::remove_dir_all(dir);
}

fn walk(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    for entry in std::fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            out.extend(walk(&path));
        } else {
            out.push(path);
        }
    }
    out
}

fn replace_word(text: &str, word: &str, by: &str) -> String {
    let is_word = |c: char| c.is_ascii_alphanumeric() || c == '_';
    let mut out = String::new();
    let mut rest = text;
    while let Some(at) = rest.find(word) {
        let before = rest[..at].chars().next_back();
        let after = rest[at + word.len()..].chars().next();
        out.push_str(&rest[..at]);
        if before.is_some_and(is_word) || after.is_some_and(is_word) {
            out.push_str(word);
        } else {
            out.push_str(by);
        }
        rest = &rest[at + word.len()..];
    }
    out.push_str(rest);
    out
}

#[test]
fn a_saved_game_continues_on_a_changed_model() {
    let dir = copy_model(&root().join("models/toy"), "session");
    edit(&dir.join("economy.toml"), |text| text + OLD_COUNTER);
    let path = dir.join("scenarios/baseline.toml");
    let mut session = Session::open(&path).unwrap();
    for _ in 0..4 {
        session.step().unwrap();
    }
    session.set_lever("basic_rate", toml::Value::Float(0.25)).unwrap();
    session.step().unwrap();
    let bytes = session.save();
    assert!(session.latest("old_counter").is_some());

    next_version(&dir);
    let mut loaded = Session::load(&path, &bytes).unwrap();
    let migration = loaded.migration().expect("the model changed");
    assert_eq!(migration.clamped, vec!["basic_rate".to_string()]);
    assert_eq!(loaded.latest("basic_rate"), Some(Val::F(0.22)));
    assert_eq!(loaded.latest("old_counter"), None);
    assert_eq!(loaded.steps_done(), 5);
    assert_eq!(loaded.changes().len(), 1, "the game's record of policy changes is kept");
    loaded.step().unwrap();
    assert_eq!(loaded.latest("months_run"), Some(Val::I(1)));
    let _ = std::fs::remove_dir_all(dir);
}

/// Run by hand with POLISIM_OLD_UK set to an older version of models/uk (for example
/// `git worktree add /tmp/s63 c6b8d43`, then /tmp/s63/models/uk): a game saved under it
/// after a year loads under the current model and plays on for another.
#[test]
#[ignore]
fn a_uk_game_saved_under_an_older_model_plays_on() {
    let old = PathBuf::from(std::env::var("POLISIM_OLD_UK").expect("POLISIM_OLD_UK"));
    let scenario = load_scenario(&old.join("scenarios/2025.toml")).unwrap();
    let model = Arc::new(scenario.model.clone());
    let mut sim = Simulation::new(Arc::clone(&model), scenario.config()).unwrap();
    for _ in 0..12 {
        sim.step().unwrap();
    }
    let gdp = sim.scalar("gdp");
    let bytes = sim.save();
    let scenario = load_scenario(&root().join("models/uk/scenarios/2025.toml")).unwrap();
    let current = Arc::new(scenario.model.clone());
    let (mut moved, migration) =
        Simulation::migrate(current, &bytes, &scenario.preset, scenario.params.clone()).unwrap();
    let migration = migration.expect("the model changed");
    println!(
        "carried {}, started again {:?}, clamped {:?}, dropped {:?}, renamed {:?}",
        migration.carried, migration.reset, migration.clamped, migration.dropped, migration.renamed
    );
    println!("GDP at the save {gdp:?}");
    for month in 13..=24 {
        moved.step().unwrap();
        if month == 13 || month == 24 {
            println!("month {month}: GDP {:?}", moved.scalar("gdp"));
        }
    }
}
