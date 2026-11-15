//! Stage S13.1: looking ahead. A forecast must equal actually making the change and playing
//! those months; forks, effects and records must never disturb the game; a vote preview
//! must agree with what the legislature then does.

use std::path::PathBuf;
use std::sync::Mutex;

use polisim_core::{Effect, Outlook, Session, Val};
use toml::Value;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn open(scenario: &str, months: u64) -> Session {
    let mut session = Session::open(&root().join(scenario)).unwrap();
    for _ in 0..months {
        session.step().unwrap();
    }
    session
}

fn row(outlook: &Outlook, name: &str) -> f64 {
    match outlook.rows.iter().find(|(n, _)| n == name).map(|(_, v)| *v) {
        Some(Val::F(v)) => v,
        Some(Val::I(v)) => v as f64,
        other => panic!("{name}: {other:?}"),
    }
}

/// Every row and cell of a look ahead against the game after playing the same months,
/// leaving out the rows named.
fn assert_played(outlook: &Outlook, session: &Session, except: &[&str]) {
    for (name, value) in outlook.rows.iter().filter(|(n, _)| !except.contains(&n.as_str())) {
        assert_eq!(session.latest(name), Some(*value), "{name}");
    }
    for (name, cells) in &outlook.cells {
        assert_eq!(session.cells(name), Some(cells.as_slice()), "{name}");
    }
}

#[test]
fn a_forecast_equals_playing_the_months_without_a_legislature() {
    let scenario = "models/valmora/scenarios/term.toml";
    let mut session = open(scenario, 2);
    session.set_lever("vat_rate", Value::Float(0.22)).unwrap();
    let forecast = session.forecast(&[("basic_rate".to_string(), Value::Float(0.25))], 6).unwrap();
    assert_eq!(forecast.months, 6);
    assert_ne!(forecast.as_is.hash, forecast.changed.hash);

    // "As is" is the game with the change waiting, played.
    for _ in 0..6 {
        session.step().unwrap();
    }
    assert_eq!(forecast.as_is.hash, *session.history().hashes.last().unwrap());
    assert_played(&forecast.as_is, &session, &[]);

    let mut changed = open(scenario, 2);
    changed.set_lever("vat_rate", Value::Float(0.22)).unwrap();
    changed.set_lever("basic_rate", Value::Float(0.25)).unwrap();
    for _ in 0..6 {
        changed.step().unwrap();
    }
    assert_eq!(forecast.changed.hash, *changed.history().hashes.last().unwrap());
    assert_played(&forecast.changed, &changed, &[]);
}

#[test]
fn on_the_uk_a_forecast_equals_playing_when_the_bill_passes_and_is_affordable() {
    let scenario = "models/uk/scenarios/2025.toml";
    let mut session = open(scenario, 1);
    let forecast = session.forecast(&[("basic_rate".to_string(), Value::Float(0.21))], 3).unwrap();
    session.set_lever("basic_rate", Value::Float(0.21)).unwrap();
    for _ in 0..3 {
        session.step().unwrap();
    }
    let change = &session.changes()[0];
    assert!(change.passed && !change.refused, "{change:?}");
    // A fork does not pay for the bill, so only the capital differs.
    assert_played(&forecast.changed, &session, &["political_capital", "capital_spent"]);
    assert!(!forecast.changed.cells.is_empty());
    let Some(Val::F(paid)) = session.latest("political_capital") else { panic!("no capital") };
    assert!(row(&forecast.changed, "political_capital") > paid, "the fork kept the bill's cost");
}

#[test]
fn forecasts_effects_and_records_leave_the_game_as_it_was() {
    let scenario = "models/uk/scenarios/2025.toml";
    let mut looked = open(scenario, 1);
    let mut plain = open(scenario, 1);
    for session in [&mut looked, &mut plain] {
        session.set_lever("vat_rate", Value::Float(0.21)).unwrap();
    }
    looked.forecast(&[("basic_rate".to_string(), Value::Float(0.3))], 2).unwrap();
    looked.fork().unwrap().effects(&["basic_rate".to_string()], 2, 2, &|| false, &|_| {});
    looked.records("household", "", 5, &["net_income".to_string()]).unwrap();
    looked.vote_preview("basic_rate", &Value::Float(0.3)).unwrap();
    looked.step().unwrap();
    plain.step().unwrap();
    assert_eq!(looked.history().hashes, plain.history().hashes);
    assert_eq!(looked.changes(), plain.changes());
}

#[test]
fn the_uk_effects_table_moves_receipts_incomes_and_prices_the_right_way() {
    let session = open("models/uk/scenarios/2025.toml", 1);
    let levers: Vec<String> = ["basic_rate", "vat_rate", "capital_spent"].iter().map(|s| s.to_string()).collect();
    let found: Mutex<Vec<Effect>> = Mutex::new(Vec::new());
    session.fork().unwrap().effects(&levers, 12, 2, &|| false, &|e| found.lock().unwrap().push(e));
    let found = found.into_inner().unwrap();
    assert_eq!(found.len(), 3);
    let effect = |lever: &str| found.iter().find(|e| e.lever == lever).unwrap();

    let basic = effect("basic_rate");
    assert!(basic.step > 0.0, "{}", basic.step);
    let f = basic.forecast.as_ref().unwrap();
    assert!(row(&f.changed, "income_tax") > row(&f.as_is, "income_tax"));
    assert!(row(&f.changed, "net_income_average") < row(&f.as_is, "net_income_average"));

    let vat = effect("vat_rate").forecast.as_ref().unwrap();
    assert!(row(&vat.changed, "consumer_price_index") > row(&vat.as_is, "consumer_price_index"));
    assert_eq!(vat.as_is, f.as_is, "one shared as-is branch");

    assert!(effect("capital_spent").forecast.is_err(), "the engine sets it");
}

#[test]
fn an_effects_run_stops_when_told() {
    let session = open("models/valmora/scenarios/term.toml", 1);
    let levers: Vec<String> = ["basic_rate", "vat_rate", "higher_rate"].iter().map(|s| s.to_string()).collect();
    let count = Mutex::new(0);
    session.fork().unwrap().effects(&levers, 2, 1, &|| *count.lock().unwrap() >= 1, &|_| *count.lock().unwrap() += 1);
    assert_eq!(count.into_inner().unwrap(), 1);
}

#[test]
fn a_vote_preview_agrees_with_a_passing_bill() {
    let mut session = open("models/uk/scenarios/2025.toml", 1);
    let preview = session.vote_preview("basic_rate", &Value::Float(0.21)).unwrap();
    assert!(preview.bill && preview.passes && preview.affordable, "{preview:?}");
    session.set_lever("basic_rate", Value::Float(0.21)).unwrap();
    session.step().unwrap();
    let change = &session.changes()[0];
    assert!(change.passed);
    assert_eq!((preview.votes_for, preview.seats, preview.cost), (change.votes_for, change.seats, change.cost));
}

#[test]
fn a_vote_preview_agrees_with_a_defeated_bill() {
    let mut session = open("models/uk/scenarios/early_election.toml", 2);
    let preview = session.vote_preview("basic_rate", &Value::Float(0.18)).unwrap();
    assert!(preview.bill && !preview.passes && preview.affordable, "{preview:?}");
    session.set_lever("basic_rate", Value::Float(0.18)).unwrap();
    session.step().unwrap();
    let change = &session.changes()[0];
    assert!(!change.passed && !change.refused);
    assert_eq!((preview.votes_for, preview.seats), (283, 650));
    assert_eq!((preview.votes_for, preview.seats, preview.cost), (change.votes_for, change.seats, change.cost));
}

#[test]
fn a_vote_preview_counts_the_bills_waiting_and_agrees_with_a_refusal() {
    let mut session = open("models/uk/scenarios/2025.toml", 1);
    session.set_lever("basic_rate", Value::Float(0.8)).unwrap();
    let alone = session.vote_preview("basic_rate", &Value::Float(0.8)).unwrap();
    assert!(alone.affordable, "the waiting change it replaces is not counted: {alone:?}");
    let preview = session.vote_preview("vat_rate", &Value::Float(0.5)).unwrap();
    assert!(preview.bill && !preview.affordable, "{preview:?}");
    session.set_lever("vat_rate", Value::Float(0.5)).unwrap();
    session.step().unwrap();
    let change = session.changes().iter().find(|c| c.lever == "vat_rate").unwrap();
    assert!(change.refused && !change.passed);
    assert_eq!(preview.cost, change.cost);
    assert!(session.vote_preview("capital_spent", &Value::Float(1.0)).is_err());
    assert!(session.vote_preview("vat_rate", &Value::Float(2.0)).is_err(), "outside the range");
}

#[test]
fn a_change_with_no_leaning_or_no_legislature_is_no_bill() {
    let session = open("models/valmora/scenarios/term.toml", 1);
    let preview = session.vote_preview("basic_rate", &Value::Float(0.3)).unwrap();
    assert!(!preview.bill && preview.passes && preview.affordable && preview.cost.is_none());
}

#[test]
fn records_are_the_same_each_time_and_respect_the_condition() {
    let session = open("models/uk/scenarios/2025.toml", 1);
    let columns = vec!["net_income".to_string(), "self_employed1".to_string()];
    let first = session.records("household", "uc_couple_unit", 12, &columns).unwrap();
    assert_eq!(first, session.records("household", "uc_couple_unit", 12, &columns).unwrap());
    assert_eq!(first.len(), 12);

    let all = session.records("household", "", usize::MAX, &["uc_couple_unit".to_string()]).unwrap();
    assert!(all.len() > 1000);
    let couple = |id: u64| all.iter().find(|r| r.id == id).unwrap().values[0].1 == Val::B(true);
    for record in &first {
        assert!(couple(record.id), "{record:?}");
        assert!(record.weight >= 1);
        assert!(matches!(record.values[0], (ref n, Val::I(_)) if n == "net_income"));
    }
    // Spread across the records, not the first twelve.
    let matching: Vec<u64> = all.iter().filter(|r| couple(r.id)).map(|r| r.id).collect();
    assert_eq!(first[0].id, matching[0]);
    assert!(first[11].id > matching[11]);

    let formula = session.records("household", "age1 >= 65", 5, &[]).unwrap();
    assert_eq!(formula.len(), 5);
    let error = session.records("household", "", 5, &["nonsense".to_string()]).unwrap_err().to_string();
    assert!(error.contains("nonsense"), "{error}");
    let error = session.records("household", "no_such_flag", 5, &[]).unwrap_err().to_string();
    assert!(error.contains("no_such_flag"), "{error}");
}
