//! Stage S14.3: a responsive engine changes no result. A forecast stopped part-way leaves
//! the game untouched; the effects table is the same on any number of threads and in any
//! order; a state hash made only when asked for is the recorded one; the bridge's copy of
//! the history, built a month at a time, is the history; a saved effects table comes back
//! as it was; and the graph queries follow the dependency edges.

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use polisim_core::session::History;
use polisim_core::{Effect, Session, Simulation, Val, load_scenario, pyfmt};
use toml::Value;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

const TERM: &str = "models/valmora/scenarios/term.toml";

fn open(scenario: &str, months: u64) -> Session {
    let mut session = Session::open(&root().join(scenario)).unwrap();
    for _ in 0..months {
        session.step().unwrap();
    }
    session
}

#[test]
fn a_stopped_forecast_leaves_the_game_untouched_and_a_later_one_equals_playing() {
    let mut session = open(TERM, 1);
    let mut plain = open(TERM, 1);
    session.set_lever("vat_rate", Value::Float(0.22)).unwrap();
    plain.set_lever("vat_rate", Value::Float(0.22)).unwrap();
    let change = vec![("basic_rate".to_string(), Val::F(0.25))];

    // Stopped before its third month: nothing comes back.
    let asked = Mutex::new(0);
    let stop = || {
        let mut n = asked.lock().unwrap();
        *n += 1;
        *n > 2
    };
    assert_eq!(session.fork().unwrap().run_until(&change, 6, &stop).unwrap(), None);
    assert_eq!(session.fork().unwrap().forecast(None, &change, 6, &|| true).unwrap(), None);

    // A later forecast, from the shared "as is" branch or without it, equals playing.
    let fork = session.fork().unwrap();
    let as_is = fork.run(&[], 4).unwrap();
    let shared = fork.clone().forecast(Some(as_is.clone()), &change, 4, &|| false).unwrap().unwrap();
    let whole = session.forecast(&[("basic_rate".to_string(), Value::Float(0.25))], 4).unwrap();
    assert_eq!(shared, whole);
    assert_eq!(whole.as_is, as_is);

    let mut changed = open(TERM, 1);
    changed.set_lever("vat_rate", Value::Float(0.22)).unwrap();
    changed.set_lever("basic_rate", Value::Float(0.25)).unwrap();
    for _ in 0..4 {
        session.step().unwrap();
        plain.step().unwrap();
        changed.step().unwrap();
    }
    assert_eq!(session.history().hashes, plain.history().hashes, "the game was not touched");
    assert_eq!(whole.as_is.hash, *session.history().hashes.last().unwrap());
    assert_eq!(whole.changed.hash, *changed.history().hashes.last().unwrap());
}

fn table(session: &Session, levers: &[&str], threads: usize) -> BTreeMap<String, Effect> {
    let levers: Vec<String> = levers.iter().map(|s| s.to_string()).collect();
    let found = Mutex::new(BTreeMap::new());
    session.fork().unwrap().effects(&levers, 3, threads, &|| false, &|e| {
        found.lock().unwrap().insert(e.lever.clone(), e);
    });
    found.into_inner().unwrap()
}

#[test]
fn the_effects_table_is_the_same_on_any_number_of_threads_and_in_any_order() {
    let session = open(TERM, 1);
    let one = table(&session, &["basic_rate", "vat_rate", "higher_rate"], 1);
    let many = table(&session, &["higher_rate", "vat_rate", "basic_rate"], 3);
    assert_eq!(one.len(), 3);
    assert_eq!(one, many);
    for effect in one.values() {
        assert!(effect.forecast.is_ok(), "{effect:?}");
    }
}

#[test]
fn hashes_made_only_when_asked_for_are_the_recorded_ones() {
    for (scenario, golden) in [
        ("models/uk/scenarios/2025.toml", "models/uk/golden/2025.hashes.csv"),
        ("models/cohort/scenarios/base.toml", "models/cohort/golden/base.hashes.csv"),
    ] {
        let scenario = load_scenario(&root().join(scenario)).unwrap();
        let recorded = std::fs::read_to_string(root().join(golden)).unwrap();
        let golden: Vec<&str> = recorded.lines().skip(1).map(|line| line.split(',').nth(1).unwrap()).collect();
        let mut sim = Simulation::new(Arc::new(scenario.model.clone()), scenario.config()).unwrap();
        for (step, want) in golden.iter().enumerate() {
            sim.advance().unwrap();
            // Every third month only, as a look ahead asks.
            if step % 3 == 2 || step + 1 == golden.len() {
                assert_eq!(pyfmt::hex(&sim.state_hash()), *want, "at step {step}");
            }
        }
    }
}

#[test]
fn a_history_copied_a_month_at_a_time_is_the_history() {
    let mut session = open(TERM, 0);
    let mut copy = History::default();
    let mut sent = 0;
    for _ in 0..5 {
        session.step().unwrap();
        copy.append(session.history().tail(sent));
        sent = session.history().steps.len();
        copy.append(session.history().tail(sent)); // nothing new: no change
    }
    assert_eq!(&copy, session.history());
    assert_eq!(copy.series("vat_rate"), session.history().series("vat_rate"));
}

#[test]
fn a_saved_effects_table_comes_back_as_it_was() {
    let path = root().join(TERM);
    let mut session = open(TERM, 1);
    let found = table(&session, &["basic_rate", "vat_rate"], 2);
    let mut effects: Vec<Effect> = found.into_values().collect();
    effects.push(Effect {
        lever: "not_a_lever".to_string(),
        step: 0.0,
        forecast: Err(polisim_core::Error::Model("\"not_a_lever\" is not a lever".to_string())),
    });
    session.keep_effects(Some((3, effects.clone())));
    let bytes = session.save();
    let loaded = Session::load(&path, &bytes).unwrap();
    assert_eq!(loaded.effects_kept(), Some(&(3, effects)));
    assert_eq!(loaded.save(), bytes, "loading then saving gives the same file");

    // A lever change, or a month, drops it.
    let mut changed = Session::load(&path, &bytes).unwrap();
    changed.set_lever("vat_rate", Value::Float(0.21)).unwrap();
    assert_eq!(changed.effects_kept(), None);
    let mut stepped = Session::load(&path, &bytes).unwrap();
    stepped.step().unwrap();
    assert_eq!(stepped.effects_kept(), None);
}

#[test]
fn the_basic_rate_reaches_government_support_along_the_dependency_edges() {
    let session = open("models/uk/scenarios/2025.toml", 0);
    let reached = session.reach("basic_rate");
    let support = reached.iter().find(|l| l.name == "government_support").expect("reaches government support");
    assert!(reached.iter().all(|l| l.name != "basic_rate"));

    let path = session.path("basic_rate", "government_support");
    assert_eq!(path.first().map(|l| l.name.as_str()), Some("basic_rate"));
    assert_eq!(path.last().map(|l| l.name.as_str()), Some("government_support"));
    assert!(!path[0].lagged);
    let entry = |name: &str| session.catalogue().entries.iter().find(|e| e.name == name).unwrap();
    for pair in path.windows(2) {
        let reader = entry(&pair[1].name);
        let list = if pair[1].lagged { &reader.lagged_inputs } else { &reader.inputs };
        assert!(list.contains(&pair[0].name), "{} does not read {}", pair[1].name, pair[0].name);
    }
    assert_eq!(support.lagged, path.iter().any(|l| l.lagged), "the reach says what its path says");
    // Every step of a path is itself reached, and nothing reaches back to a lever.
    for link in &path[1..] {
        assert!(reached.iter().any(|l| l.name == link.name));
    }
    assert!(session.path("government_support", "basic_rate").is_empty());
    assert!(session.reach("no_such_value").is_empty());
}
