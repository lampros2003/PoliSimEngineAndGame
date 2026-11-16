//! Bills (docs/spec/06-model-format-1.md, stage S5.4): the cases in
//! conformance/bill_cases.toml, with their recorded outcomes, and the UK model's coalition
//! losing a bill, against its recorded hashes.

use std::path::PathBuf;
use std::sync::Arc;

use polisim_core::{RunConfig, Simulation, Val, load_model, load_scenario, pyfmt};
use toml::Value;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

enum Outcome {
    Refused(String),
    Runtime(String),
    Ran(Box<Simulation>),
}

fn outcome(cases: &toml::Table, case: &toml::Table, index: usize) -> Outcome {
    let mut text = cases["base"].as_str().unwrap().to_string();
    // Stage S12.4: a case with `capital = true` gives the legislature political capital first.
    let capital = case.get("capital").and_then(Value::as_bool).unwrap_or(false);
    let pairs = cases["capital"].as_array().unwrap().iter().filter(|_| capital);
    for pair in pairs.chain(case.get("replace").and_then(Value::as_array).into_iter().flatten()) {
        let pair = pair.as_array().unwrap();
        let old = pair[0].as_str().unwrap().replace("\\n", "\n");
        let new = pair[1].as_str().unwrap().replace("\\n", "\n");
        assert_eq!(text.matches(&old).count(), 1, "{old:?}");
        text = text.replace(&old, &new);
    }
    let dir = std::env::temp_dir().join(format!("polisim-bills-{}-{index}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("model.toml"), text).unwrap();
    let mut files = cases["files"].as_table().unwrap().clone();
    if let Some(extra) = case.get("files").and_then(Value::as_table) {
        files.extend(extra.clone());
    }
    for (name, content) in &files {
        std::fs::write(dir.join(name), content.as_str().unwrap()).unwrap();
    }
    let commands: Vec<(u64, String, Value)> = case
        .get("set")
        .and_then(Value::as_table)
        .map(|t| t.iter().map(|(k, v)| (0, k.clone(), v.clone())).collect())
        .unwrap_or_default();
    let result = (|| {
        let model = match load_model(&dir) {
            Ok(m) => m,
            Err(e) => return Outcome::Refused(e.to_string()),
        };
        let config = RunConfig { commands, ..RunConfig::default() };
        let mut sim = match Simulation::new(Arc::new(model), config) {
            Ok(s) => s,
            Err(e) => return Outcome::Refused(e.to_string()),
        };
        match sim.step() {
            Ok(_) => Outcome::Ran(Box::new(sim)),
            Err(e) => Outcome::Runtime(e.to_string()),
        }
    })();
    std::fs::remove_dir_all(&dir).ok();
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
fn shared_cases_match_their_expectations() {
    let text = std::fs::read_to_string(root().join("conformance/bill_cases.toml")).unwrap();
    let cases: toml::Table = text.parse().unwrap();
    let list = cases["case"].as_array().unwrap();
    assert!(list.len() >= 20);
    for (index, case) in list.iter().enumerate() {
        let case = case.as_table().unwrap();
        let name = case["name"].as_str().unwrap();
        let expect = case["expect"].as_str().unwrap();
        match (outcome(&cases, case, index), expect) {
            (Outcome::Ran(sim), "ran") => {
                for (lever, want) in case["levers"].as_table().unwrap() {
                    assert!(same(sim.scalar(lever), want), "{name}: {lever} is {:?}, not {want:?}", sim.scalar(lever));
                }
                // Stage S12.4: an expected vote may also give its cost and whether it was refused.
                let want = case["votes"].as_array().unwrap();
                assert_eq!(sim.votes().len(), want.len(), "{name}: {:?}", sim.votes());
                for (v, w) in sim.votes().iter().zip(want) {
                    let w = w.as_array().unwrap();
                    let got = (v.lever.as_str(), v.votes_for, v.passed);
                    let expected = (w[0].as_str().unwrap(), w[1].as_integer().unwrap(), w[2].as_bool().unwrap());
                    assert_eq!(got, expected, "{name}");
                    if w.len() == 5 {
                        assert_eq!(v.cost, w[3].as_float(), "{name}: the cost of {}", v.lever);
                        assert_eq!(v.refused, w[4].as_bool().unwrap(), "{name}: {} refused", v.lever);
                    }
                }
            }
            (Outcome::Refused(_), "refused") | (Outcome::Runtime(_), "runtime") => {}
            (Outcome::Refused(e), _) => panic!("{name}: refused ({e}), expected {expect}"),
            (Outcome::Runtime(e), _) => panic!("{name}: failed at run time ({e}), expected {expect}"),
            (Outcome::Ran(_), _) => panic!("{name}: ran, expected {expect}"),
        }
    }
}

#[test]
fn a_coalition_loses_a_bill_as_recorded() {
    let scenario = load_scenario(&root().join("models/uk/scenarios/coalition_bill.toml")).unwrap();
    let recorded = std::fs::read_to_string(root().join("models/uk/golden/coalition_bill.hashes.csv")).unwrap();
    let golden: Vec<&str> = recorded.lines().skip(1).map(|line| line.split(',').nth(1).unwrap()).collect();
    let mut sim = Simulation::new(Arc::new(scenario.model.clone()), scenario.config()).unwrap();
    for (step, want) in golden.iter().enumerate() {
        let row = sim.step().unwrap();
        assert_eq!(
            pyfmt::hex(&row.hash),
            *want,
            "coalition bill state hash differs from the recorded hash at step {step}"
        );
    }
    let votes: Vec<(&str, i64, bool)> = sim.votes().iter().map(|v| (v.lever.as_str(), v.votes_for, v.passed)).collect();
    assert_eq!(votes, [("basic_rate", 283, false), ("personal_allowance", 283, false), ("vat_rate", 627, true)]);
}

/// Stage S12.4: in the UK, two big bills in one month: the first is paid for, the second
/// costs more than is left and is refused unvoted; the costs and the refusal survive a save.
#[test]
fn a_game_refuses_a_bill_it_cannot_pay_for_and_keeps_it_through_a_save() {
    use polisim_core::Session;
    let path = root().join("models/uk/scenarios/2025.toml");
    let mut session = Session::open(&path).unwrap();
    session.step().unwrap();
    let Some(Val::F(capital)) = session.latest("political_capital") else { panic!("no political capital") };
    session.set_lever("basic_rate", Value::Float(0.5)).unwrap();
    session.set_lever("vat_rate", Value::Float(0.35)).unwrap();
    session.step().unwrap();
    let changes = session.changes();
    // Stage S13.7: both rates weigh 2. 5 + 60 * 2 * 0.3 / 1 and 5 + 60 * 2 * 0.15 / 0.5: 41
    // each, against about 47 to spend.
    let find = |lever: &str| changes.iter().find(|c| c.lever == lever).unwrap();
    let (first, second) = (find("basic_rate"), find("vat_rate"));
    assert!((first.lever.as_str(), first.passed, first.refused) == ("basic_rate", true, false), "{first:?}");
    assert!((second.lever.as_str(), second.passed, second.refused) == ("vat_rate", false, true), "{second:?}");
    assert!((first.cost.unwrap() - 41.0).abs() < 1e-9 && (second.cost.unwrap() - 41.0).abs() < 1e-9);
    assert!(capital > 41.0 && capital < 82.0, "capital {capital}");
    assert_eq!(session.latest("capital_spent"), Some(Val::F(first.cost.unwrap())));
    assert_eq!(session.latest("vat_rate"), Some(Val::F(0.2)));
    assert!(session.set_lever("capital_spent", Value::Float(0.0)).is_err(), "the player set what bills spent");
    let loaded = Session::load(&path, &session.save()).unwrap();
    assert_eq!(loaded.changes(), session.changes());
}

#[test]
fn a_game_records_the_defeat_and_keeps_it_through_a_save() {
    use polisim_core::Session;
    let path = root().join("models/uk/scenarios/early_election.toml");
    let mut session = Session::open(&path).unwrap();
    session.step().unwrap();
    session.step().unwrap();
    session.set_lever("basic_rate", Value::Float(0.18)).unwrap();
    session.step().unwrap();
    let change = &session.changes()[0];
    assert_eq!((change.lever.as_str(), change.passed, change.votes_for, change.seats), ("basic_rate", false, 283, 650));
    assert_eq!(session.latest("basic_rate"), Some(Val::F(0.2)));
    let loaded = Session::load(&path, &session.save()).unwrap();
    assert_eq!(loaded.changes(), session.changes());
}
