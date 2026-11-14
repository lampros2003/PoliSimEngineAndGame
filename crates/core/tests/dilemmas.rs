//! Stage S9.1: dilemmas. The shared cases in conformance/dilemma_cases.toml, which the
//! oracle runs too (oracle/tests/test_dilemmas.py), and what a save holds between steps.

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use polisim_core::{RunConfig, Simulation, Val, load_model};
use toml::Value;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn folder(model_text: &str) -> PathBuf {
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let n = NEXT.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::temp_dir().join(format!("polisim-dilemmas-{}-{n}", std::process::id()));
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

fn run(model_text: &str, answers: Vec<(u64, String, Value)>, steps: usize, names: &[String]) -> Outcome {
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
        sim.set_commands(answers);
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
    std::fs::read_to_string(root().join("conformance/dilemma_cases.toml")).unwrap().parse().unwrap()
}

#[test]
fn shared_cases_match_the_oracle() {
    let cases = cases();
    let base = cases["base"].as_str().unwrap();
    let list = cases["case"].as_array().unwrap();
    assert!(list.len() >= 30);
    for case in list {
        let case = case.as_table().unwrap();
        let name = case["name"].as_str().unwrap();
        let add = case["add"].as_str().unwrap().replace("\\n", "\n");
        let steps = case["steps"].as_integer().unwrap() as usize;
        let answers: Vec<(u64, String, Value)> = case
            .get("answers")
            .and_then(Value::as_array)
            .map(|list| {
                list.iter()
                    .map(|a| {
                        let a = a.as_array().unwrap();
                        (a[0].as_integer().unwrap() as u64, a[1].as_str().unwrap().to_string(), a[2].clone())
                    })
                    .collect()
            })
            .unwrap_or_default();
        let names: Vec<String> =
            case.get("series").and_then(Value::as_table).map(|s| s.keys().cloned().collect()).unwrap_or_default();
        let outcome = run(&format!("{base}\n{add}\n"), answers, steps, &names);
        match (case["expect"].as_str().unwrap(), outcome) {
            ("ran", Outcome::Ran(after)) => {
                for (i, (value, series)) in case["series"].as_table().unwrap().iter().enumerate() {
                    for (step, want) in series.as_array().unwrap().iter().enumerate() {
                        let got = after[step][i];
                        assert!(same(got, want), "{name}: {value} after step {step} is {got:?}, the oracle {want:?}");
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

const ADD: &str = "[dilemma.d]\nlabel = \"D\"\ndoc = \"A question\"\nstart = \"count >= 2\"\nagain_after = 12\n\
[[dilemma.d.option]]\nname = \"a\"\nlabel = \"Yes\"\nmonths = 3\neffect = { cost = \"{base} + 1.0\" }\n\
[[dilemma.d.option]]\nname = \"b\"\ndoc = \"No\"";

#[test]
fn the_model_keeps_each_dilemma() {
    let cases = cases();
    let dir = folder(&format!("{}\n{ADD}\n", cases["base"].as_str().unwrap()));
    let model = load_model(&dir).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(model.dilemmas.len(), 1);
    let d = &model.dilemmas[0];
    assert_eq!((d.name.as_str(), d.label.as_str(), d.doc.as_str(), d.again_after), ("d", "D", "A question", Some(12)));
    let options: Vec<(&str, &str, &str, Option<i64>)> =
        d.options.iter().map(|o| (o.name.as_str(), o.label.as_str(), o.doc.as_str(), o.months)).collect();
    assert_eq!(options, [("a", "Yes", "", Some(3)), ("b", "b", "No", None)]);
    let mut made: Vec<&str> = model
        .symbols
        .iter()
        .filter(|s| s.spec.get("dilemma").and_then(Value::as_str) == Some("d"))
        .map(|s| s.name.as_str())
        .collect();
    made.sort();
    assert_eq!(made, ["cost_before_d", "d", "d_age", "d_answer", "d_choice", "d_months", "d_open"]);
}

#[test]
fn an_answer_is_not_a_starting_value_and_a_save_holds_the_lever_at_zero() {
    let cases = cases();
    let dir = folder(&format!("{}\n{ADD}\n", cases["base"].as_str().unwrap()));
    let model = Arc::new(load_model(&dir).unwrap());
    let _ = std::fs::remove_dir_all(&dir);
    let config = RunConfig { levers: vec![("d".to_string(), Value::Integer(1))], ..RunConfig::default() };
    assert!(Simulation::new(Arc::clone(&model), config).is_err());

    // Answered in step 2, saved after step 2, resumed: the same run as without the save.
    let answers = vec![(2, "d".to_string(), Value::Integer(1))];
    let mut straight = Simulation::new(Arc::clone(&model), RunConfig::default()).unwrap();
    straight.set_commands(answers.clone());
    let mut hashes = Vec::new();
    for _ in 0..6 {
        straight.step().unwrap();
        hashes.push(straight.state_hash());
    }
    let mut first = Simulation::new(Arc::clone(&model), RunConfig::default()).unwrap();
    first.set_commands(answers);
    for _ in 0..3 {
        first.step().unwrap();
    }
    assert_eq!(first.scalar("d"), Some(Val::I(0)));
    assert_eq!(first.scalar("d_choice"), Some(Val::I(1)));
    // Not open any more: the client is told before the month runs.
    assert!(first.check_lever("d", &Value::Integer(2)).is_err());
    let bytes = first.save();
    let mut resumed = Simulation::resume(Arc::clone(&model), &bytes).unwrap();
    for hash in &hashes[3..] {
        resumed.step().unwrap();
        assert_eq!(resumed.state_hash(), *hash);
    }
    assert_eq!(resumed.scalar("cost"), Some(Val::F(1.0)));
}

#[test]
fn a_session_knows_which_dilemmas_wait_and_their_words_in_french() {
    use polisim_core::Session;
    let mut session = Session::open(&root().join("models/valmora/scenarios/dock_strike.toml")).unwrap();
    let names: Vec<&str> = session.catalogue().dilemmas.iter().map(|d| d.name.as_str()).collect();
    assert_eq!(names, ["dock_strike_walkout"]);
    let lever = session.catalogue().entry("dock_strike_walkout").unwrap();
    assert!(!lever.player, "the dilemma's lever is not for the policy panel");
    assert_eq!(lever.dilemma, "dock_strike_walkout");
    for _ in 0..3 {
        assert!(session.unanswered_dilemmas().is_empty());
        session.step().unwrap();
    }
    assert_eq!(session.unanswered_dilemmas(), ["dock_strike_walkout"]);
    assert!(session.set_lever("dock_strike_walkout", Value::Integer(3)).is_err());
    session.set_lever("dock_strike_walkout", Value::Integer(2)).unwrap();
    assert!(session.unanswered_dilemmas().is_empty());
    session.step().unwrap();
    assert_eq!(session.latest("dock_strike_walkout_choice"), Some(Val::I(2)));
    assert!(session.unanswered_dilemmas().is_empty());

    session.set_language("fr").unwrap();
    let d = &session.catalogue().dilemmas[0];
    assert_eq!(d.label, "Grève des dockers");
    let labels: Vec<&str> = d.options.iter().map(|o| o.label.as_str()).collect();
    assert_eq!(labels, ["Payer les dockers", "Attendre"]);
    assert_eq!(session.catalogue().entry("dock_strike_walkout").unwrap().label, "Grève des dockers");
}

#[test]
fn a_translation_that_leaves_a_dilemma_out_says_so() {
    let scenario = polisim_core::load_scenario(&root().join("models/valmora/scenarios/dock_strike.toml")).unwrap();
    let mut text = polisim_core::load_text(&scenario.model, "fr").unwrap().unwrap();
    assert!(text.missing(&scenario.model).is_empty());
    let words = text.table.get_mut("dilemma").and_then(Value::as_table_mut).unwrap();
    let strike = words.get_mut("dock_strike_walkout").and_then(Value::as_table_mut).unwrap();
    strike.remove("doc");
    strike.get_mut("option").and_then(Value::as_table_mut).unwrap().remove("wait");
    assert_eq!(
        text.missing(&scenario.model),
        [
            "dilemma.dock_strike_walkout.doc",
            "dilemma.dock_strike_walkout.option.wait.label",
            "dilemma.dock_strike_walkout.option.wait.doc"
        ]
    );
}
