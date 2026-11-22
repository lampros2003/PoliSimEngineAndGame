//! Explanations and reload: both observe or restructure a run and must never change it.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use polisim_core::model::Kind;
use polisim_core::{Num, Simulation, load_model, load_scenario};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn baseline() -> (Arc<polisim_core::Model>, polisim_core::RunConfig) {
    let mut scenario = load_scenario(&root().join("models/toy/scenarios/baseline.toml")).unwrap();
    // Policy changes inside the window, so levers move and their effects can be traced.
    scenario.commands.push((5, "basic_rate".to_string(), toml::Value::Float(0.24)));
    scenario.commands.push((9, "gov_purchases".to_string(), toml::Value::Integer(1_600_000_000)));
    (Arc::new(scenario.model.clone()), scenario.config())
}

#[test]
fn tracing_changes_no_result() {
    let (model, config) = baseline();
    let mut plain = Simulation::new(Arc::clone(&model), config.clone()).unwrap();
    let mut traced = Simulation::new(model, config).unwrap();
    traced.set_tracing(true);
    for _ in 0..30 {
        assert_eq!(plain.step().unwrap(), traced.step().unwrap());
    }
}

#[test]
fn every_value_is_reproduced_and_explained() {
    let (model, config) = baseline();
    let mut sim = Simulation::new(Arc::clone(&model), config).unwrap();
    sim.set_tracing(true);
    sim.step().unwrap();
    assert!(sim.explain("gdp").is_err(), "one step is not enough history");
    for _ in 0..14 {
        sim.step().unwrap();
        for d in &model.symbols {
            // explain() re-evaluates the formula from the snapshots and fails unless it
            // reproduces the stored value exactly.
            let e = sim.explain(&d.name).unwrap_or_else(|err| panic!("{}: {err}", d.name));
            match (e.change, e.remainder) {
                (Num::Int(change), Num::Int(rest)) => {
                    let parts: i128 = e
                        .parts
                        .iter()
                        .filter_map(|p| p.effect)
                        .map(|n| match n {
                            Num::Int(v) => v,
                            Num::Real(_) => panic!("{}: real effect on a whole-number value", d.name),
                        })
                        .sum();
                    assert_eq!(parts + rest, change, "{}", d.name);
                }
                (change, rest) => {
                    let parts: f64 = e.parts.iter().filter_map(|p| p.effect).map(Num::as_f64).sum();
                    let gap = (parts + rest.as_f64() - change.as_f64()).abs();
                    assert!(gap <= 1e-9 * change.as_f64().abs().max(1.0), "{}", d.name);
                }
            }
        }
    }
}

#[test]
fn sums_and_accounts_are_explained_exactly() {
    let (model, config) = baseline();
    let mut sim = Simulation::new(model, config).unwrap();
    sim.set_tracing(true);
    for _ in 0..12 {
        sim.step().unwrap();
    }
    // gov_balance = income_tax_total + vat - gov_spending - benefits_total
    let balance = sim.explain("gov_balance").unwrap();
    assert_eq!(balance.remainder, Num::Int(0));
    assert_eq!(balance.parts.len(), 4);
    // An account's change is exactly its flows in minus its flows out.
    let money = sim.explain("gov_money").unwrap();
    assert_eq!(money.remainder, Num::Int(0));
    let names: Vec<&str> = money.parts.iter().map(|p| p.label.as_str()).collect();
    for flow in ["income_tax", "vat", "gov_spending", "benefits"] {
        assert!(names.contains(&flow), "{names:?}");
    }
    // Last step's government purchases rose by 110m pounds; the explanation of the
    // spending flow must say so, all of it caused by the lever.
    let spending = sim.explain("gov_spending").unwrap();
    assert_eq!(spending.kind, Kind::Flow);
    let lever = sim.explain("gov_purchases").unwrap();
    assert_eq!(lever.note.as_deref(), Some("set by the player"));
    // Random draws show up as a cause of employment changes.
    let employed = sim.explain("employed").unwrap();
    assert!(employed.parts.iter().any(|p| p.label == "random draws"));
    assert_eq!(employed.entity.as_deref(), Some("household"));
}

#[test]
fn spending_change_is_traced_to_the_lever() {
    let (model, config) = baseline();
    let mut sim = Simulation::new(model, config).unwrap();
    sim.set_tracing(true);
    for _ in 0..10 {
        sim.step().unwrap(); // steps 0..=9; the lever changes in step 9
    }
    let e = sim.explain("gov_spending").unwrap();
    assert_eq!(e.step, 9);
    assert_eq!(e.change, Num::Int((1_600_000_000 - 1_490_000_000) * 100));
    assert_eq!(e.parts[0].label, "gov_purchases");
    assert_eq!(e.parts[0].effect, Some(e.change));
    assert_eq!(e.remainder, Num::Int(0));
}

fn copy_model(to: &Path) {
    let from = root().join("models/toy");
    std::fs::create_dir_all(to.join("data")).unwrap();
    for file in ["model.toml", "economy.toml", "data/households.csv"] {
        std::fs::copy(from.join(file), to.join(file)).unwrap();
    }
}

#[test]
fn reloading_an_unchanged_model_changes_nothing() {
    let (model, config) = baseline();
    let mut straight = Simulation::new(Arc::clone(&model), config.clone()).unwrap();
    let rows: Vec<_> = (0..40).map(|_| straight.step().unwrap()).collect();

    let mut sim = Simulation::new(Arc::clone(&model), config.clone()).unwrap();
    for row in &rows[..20] {
        assert_eq!(&sim.step().unwrap(), row);
    }
    let fresh = Arc::new(load_model(&root().join("models/toy")).unwrap());
    let (mut reloaded, reset) = sim.reload(fresh, &config.preset, config.params.clone()).unwrap();
    assert!(reset.is_empty(), "{reset:?}");
    for row in &rows[20..] {
        assert_eq!(&reloaded.step().unwrap(), row);
    }
}

#[test]
fn reloading_a_changed_model_keeps_the_state_and_applies_the_change() {
    let folder = std::env::temp_dir().join(format!("polisim-reload-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&folder);
    copy_model(&folder);
    let (model, config) = baseline();
    let mut before = Simulation::new(model, config.clone()).unwrap();
    for _ in 0..20 {
        before.step().unwrap();
    }
    let gov_money = before.scalar("gov_money");
    let rate = before.scalar("basic_rate");

    // Households now spend 85% of income instead of 80%, and the default VAT rate changes
    // (which must not matter: the lever's current setting is carried across).
    let economy = std::fs::read_to_string(folder.join("economy.toml")).unwrap();
    let economy = economy.replace("central = 0.80", "central = 0.85").replace(
        "default = 0.20\nrange = [0, 1]\ndoc = \"Value added tax",
        "default = 0.30\nrange = [0, 1]\ndoc = \"Value added tax",
    );
    std::fs::write(folder.join("economy.toml"), economy).unwrap();
    let changed = Arc::new(load_model(&folder).unwrap());
    let (mut after, reset) = before.reload(changed, &config.preset, config.params.clone()).unwrap();
    assert!(reset.is_empty(), "{reset:?}");
    assert_eq!(after.steps_done(), 20);
    assert_eq!(after.scalar("gov_money"), gov_money);
    assert_eq!(after.scalar("basic_rate"), rate);
    assert_eq!(after.scalar("vat_rate"), Some(polisim_core::Val::F(0.20)));

    let mut unchanged = Simulation::new(baseline().0, config).unwrap();
    for _ in 0..20 {
        unchanged.step().unwrap();
    }
    let spend = |row: &polisim_core::Row, names: &[String]| {
        let i = names.iter().position(|n| n == "consumption.total").unwrap();
        match row.values[i] {
            polisim_core::Val::I(v) => v,
            _ => unreachable!(),
        }
    };
    let a = after.step().unwrap();
    let b = unchanged.step().unwrap();
    assert!(
        spend(&a, after.row_names()) > spend(&b, unchanged.row_names()),
        "a higher propensity must raise spending at once"
    );
    let _ = std::fs::remove_dir_all(&folder);
}
