//! A game session must run exactly like a scripted run with the same lever changes, and
//! a saved game must continue exactly, charts included.

use std::path::PathBuf;
use std::sync::Arc;

use polisim_core::model::Kind;
use polisim_core::{Catalogue, Session, Simulation, Val, load_scenario};
use toml::Value;

fn baseline() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../models/toy/scenarios/baseline.toml")
}

fn play(session: &mut Session, steps: u64) {
    for _ in 0..steps {
        let at = session.steps_done();
        if at == 6 {
            session.set_lever("basic_rate", Value::Float(0.25)).unwrap();
            session.set_lever("vat_rate", Value::Float(0.22)).unwrap();
            session.cancel_lever("vat_rate");
        }
        if at == 15 {
            session.set_lever("gov_purchases", Value::Integer(1_550_000_000)).unwrap();
        }
        session.step().unwrap();
    }
}

#[test]
fn interactive_changes_equal_scripted_commands() {
    let mut session = Session::open(&baseline()).unwrap();
    play(&mut session, 30);

    let mut scenario = load_scenario(&baseline()).unwrap();
    scenario.commands.push((6, "basic_rate".to_string(), Value::Float(0.25)));
    scenario.commands.push((15, "gov_purchases".to_string(), Value::Integer(1_550_000_000)));
    let mut scripted = Simulation::new(Arc::new(scenario.model.clone()), scenario.config()).unwrap();
    let hashes: Vec<[u8; 32]> = (0..30).map(|_| scripted.step().unwrap().hash).collect();
    assert_eq!(session.history().hashes, hashes);

    let changes = session.changes();
    assert_eq!(changes.len(), 2);
    assert_eq!((changes[0].step, changes[0].lever.as_str(), changes[0].value), (6, "basic_rate", Val::F(0.25)));
    assert_eq!(changes[1].lever, "gov_purchases");
    assert_eq!(session.latest("gov_purchases"), Some(Val::I(155_000_000_000)));
}

#[test]
fn pending_changes_and_refusals() {
    let mut session = Session::open(&baseline()).unwrap();
    session.step().unwrap();
    assert!(session.pending().is_empty());
    session.set_lever("basic_rate", Value::Float(0.3)).unwrap();
    session.set_lever("basic_rate", Value::Float(0.31)).unwrap();
    assert_eq!(session.pending(), vec![("basic_rate".to_string(), Val::F(0.31))]);
    assert!(session.set_lever("vat_rate", Value::Float(1.5)).is_err(), "outside the declared range");
    assert!(session.set_lever("gdp", Value::Integer(1)).is_err(), "not a lever");
    assert_eq!(session.latest("basic_rate"), Some(Val::F(0.2)));
    session.step().unwrap();
    assert!(session.pending().is_empty());
    assert_eq!(session.latest("basic_rate"), Some(Val::F(0.31)));
    assert_eq!(session.previous("basic_rate"), Some(Val::F(0.2)));
}

#[test]
fn history_and_explanations() {
    let mut session = Session::open(&baseline()).unwrap();
    play(&mut session, 12);
    let gdp = session.history().series("gdp").unwrap();
    assert_eq!(gdp.len(), 12);
    assert_eq!(Some(Val::I(gdp[11] as i64)), session.latest("gdp"));
    let why = session.explain("gov_balance").unwrap();
    assert_eq!(why.step, 11);
}

#[test]
fn saved_game_continues_exactly() {
    let mut straight = Session::open(&baseline()).unwrap();
    play(&mut straight, 40);

    let mut first = Session::open(&baseline()).unwrap();
    play(&mut first, 10);
    first.set_lever("higher_rate", Value::Float(0.45)).unwrap(); // pending at the moment of saving
    let bytes = first.save();
    let mut second = Session::load(&baseline(), &bytes).unwrap();
    assert_eq!(second.save(), bytes, "loading then saving gives the same file");
    assert_eq!(second.pending(), vec![("higher_rate".to_string(), Val::F(0.45))]);
    second.cancel_lever("higher_rate");
    // The rest of the game, with the same interactive changes.
    for _ in 10..40 {
        let at = second.steps_done();
        if at == 15 {
            second.set_lever("gov_purchases", Value::Integer(1_550_000_000)).unwrap();
        }
        second.step().unwrap();
    }
    assert_eq!(second.history().hashes, straight.history().hashes);
    assert_eq!(second.history().series("gdp"), straight.history().series("gdp"));
    assert_eq!(second.changes(), straight.changes());
    assert!(Session::load(&baseline(), &bytes[..bytes.len() - 3]).is_err());
}

#[test]
fn catalogue_describes_the_budget() {
    let session = Session::open(&baseline()).unwrap();
    let catalogue: &Catalogue = session.catalogue();
    let government = catalogue.sectors.iter().find(|s| s.name == "government").unwrap();
    assert_eq!(government.inflows, vec!["income_tax", "vat"]);
    assert_eq!(government.outflows, vec!["benefits", "gov_spending"]);
    let tax = catalogue.entry("income_tax").unwrap();
    assert_eq!(tax.row.as_deref(), Some("income_tax.total"));
    assert_eq!(tax.shown_unit, "GBP/month");
    assert_eq!(tax.from.as_deref(), Some("households"));
    let levers: Vec<&str> =
        catalogue.entries.iter().filter(|e| e.kind == Kind::Lever).map(|e| e.name.as_str()).collect();
    assert_eq!(levers.len(), 6);
    assert!(catalogue.entry("gov_purchases").unwrap().money);
}

/// A copy of the mini model with two counters updated at the end of the phase; the second
/// is limited to `limit`, so with 4 the fifth step fails after the first has already moved.
fn counting_model(folder: &std::path::Path, limit: i64) {
    let source = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../models/mini");
    std::fs::create_dir_all(folder.join("scenarios")).unwrap();
    std::fs::create_dir_all(folder.join("data")).unwrap();
    for entry in std::fs::read_dir(source.join("data")).unwrap() {
        let entry = entry.unwrap();
        std::fs::copy(entry.path(), folder.join("data").join(entry.file_name())).unwrap();
    }
    std::fs::copy(source.join("scenarios/island.toml"), folder.join("scenarios/island.toml")).unwrap();
    let model = std::fs::read_to_string(source.join("model.toml")).unwrap();
    let extra = format!(
        "\n[state.ticks]\ntype = \"int\"\nunit = \"1\"\nphase = \"pay\"\ninitial = 0\nnext = \"ticks + 1\"\n\n\
         [state.counter]\ntype = \"int\"\nunit = \"1\"\nphase = \"pay\"\ninitial = 0\nrange = [0, {limit}]\n\
         next = \"counter + 1\"\n"
    );
    std::fs::write(folder.join("model.toml"), model + &extra).unwrap();
}

#[test]
fn a_failed_step_is_undone_and_a_corrected_model_carries_on() {
    let base = std::env::temp_dir().join(format!("polisim-rollback-{}", std::process::id()));
    let (broken, fixed) = (base.join("broken"), base.join("fixed"));
    counting_model(&broken, 4);
    counting_model(&fixed, 1000);

    // The corrected model from the start: what the repaired game must reproduce.
    let mut clean = Session::open(&fixed.join("scenarios/island.toml")).unwrap();
    for _ in 0..10 {
        clean.step().unwrap();
    }

    let mut game = Session::open(&broken.join("scenarios/island.toml")).unwrap();
    for _ in 0..4 {
        game.step().unwrap();
    }
    let error = game.step().unwrap_err().to_string();
    assert!(error.contains("outside its declared range"), "{error}");
    assert_eq!(game.steps_done(), 4);
    // Failing again changes nothing: the state was put back.
    assert!(game.step().is_err());

    // Correct the file in place and reload: the game carries on from the end of month 4.
    std::fs::copy(fixed.join("model.toml"), broken.join("model.toml")).unwrap();
    game.reload().unwrap();
    for _ in 4..10 {
        game.step().unwrap();
    }
    assert_eq!(game.history().hashes, clean.history().hashes);
    std::fs::remove_dir_all(&base).ok();
}

/// Format 1: the session keeps each dimensioned value's cells after a step and the step
/// before, and the catalogue names the dimensions and their members' labels.
#[test]
fn dimensioned_cells_after_each_step() {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../models/cohort/scenarios/base.toml");
    let mut session = Session::open(&path).unwrap();
    assert!(session.cells("population").is_none(), "no cells before the first step");
    session.step().unwrap();
    let cells = session.cells("population").unwrap().to_vec();
    assert_eq!(cells.len(), 3 * 2 * 101);
    assert!(session.previous_cells("population").is_none());
    let Some(Val::F(total)) = session.latest("total_population") else { panic!("total_population") };
    let summed: f64 = cells.iter().sum();
    assert!((summed - total).abs() <= total * 1e-12, "{summed} against {total}");
    assert!(session.cells("total_population").is_none(), "a national value has no cells");
    assert!(session.cells("mortality").is_none(), "parameters are not kept");
    session.step().unwrap();
    assert_eq!(session.previous_cells("population").unwrap(), cells.as_slice());
    assert_eq!(session.cells("births").unwrap().len(), 3 * 2);

    let saved = Session::load(&path, &session.save()).unwrap();
    assert_eq!(saved.cells("births"), session.cells("births"));
    assert_eq!(saved.previous_cells("population"), session.previous_cells("population"));

    let catalogue = session.catalogue();
    let births = catalogue.entries.iter().find(|e| e.name == "births").unwrap();
    assert_eq!(births.dims, ["region", "sex"]);
    let region = catalogue.dims.iter().find(|d| d.name == "region").unwrap();
    assert_eq!(region.labels.len(), 3);
    let age = catalogue.dims.iter().find(|d| d.name == "age").unwrap();
    assert_eq!((age.labels[0].as_str(), age.labels[100].as_str()), ("0", "100"));
}
