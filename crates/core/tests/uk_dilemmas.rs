//! Stage S9.2: the UK's dilemmas (models/uk/dilemmas.toml). Each opens in a run where it
//! should; then, from a save made there, each answer is given and one month run, and every
//! element the answer's text says it changes moves that way. The value without the
//! dilemma's effects is the var the loader made for it (`<element>_before_<dilemma>`); the
//! value with them is the next such var, or the element itself.

use std::path::PathBuf;
use std::sync::Arc;

use polisim_core::model::Kind;
use polisim_core::{Col, Model, RunConfig, Simulation, Val, load_scenario};
use toml::Value;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// An answer: its dilemma, its name, and the elements it changes, '+' up, '-' down, '~'
/// some cells each way.
type Answer = (&'static str, &'static str, &'static [(&'static str, char)]);

const EXPECT: &[Answer] = &[
    ("pay_claim", "meet", &[("public_pay", '+')]),
    ("pay_claim", "split", &[("public_pay", '+'), ("treatments", '-')]),
    ("pay_claim", "refuse", &[("treatments", '-'), ("service_target", '-'), ("government_standing", '-')]),
    ("nhs_winter", "fund", &[("procurement", '+'), ("treatments", '+')]),
    ("nhs_winter", "private", &[("procurement", '+'), ("treatments", '+')]),
    ("nhs_winter", "wait", &[("government_standing", '-')]),
    ("bank_rescue", "rescue", &[("subsidies", '+'), ("government_standing", '-')]),
    ("bank_rescue", "savers", &[("business_investment", '-')]),
    ("bank_rescue", "fail", &[("business_investment", '-'), ("consumption", '-'), ("government_standing", '-')]),
    ("steelworks", "subsidise", &[("subsidies", '+'), ("government_standing", '+')]),
    ("steelworks", "nationalise", &[("public_investment", '+'), ("government_standing", '~')]),
    ("steelworks", "close", &[("exports", '-'), ("government_standing", '-')]),
    ("investor", "grant", &[("subsidies", '+'), ("business_investment", '+'), ("exports", '+')]),
    ("investor", "decline", &[]),
    ("energy_shock", "cap", &[("subsidies", '+'), ("inflation", '+')]),
    ("energy_shock", "target", &[("benefits", '+'), ("inflation", '+'), ("government_standing", '+')]),
    ("energy_shock", "market", &[("inflation", '+'), ("government_standing", '-')]),
    ("water_company", "administer", &[("public_investment", '+')]),
    ("water_company", "customers", &[("inflation", '+'), ("government_standing", '-')]),
    ("defence_summit", "pledge", &[("procurement", '+'), ("government_standing", '+')]),
    ("defence_summit", "plans", &[("government_standing", '-')]),
    ("prisons_full", "release", &[("government_standing", '-')]),
    ("prisons_full", "build", &[("public_investment", '+'), ("service_target", '+')]),
    ("prisons_full", "community", &[("service_target", '+'), ("government_standing", '-')]),
    ("universities", "bail_out", &[("procurement", '+')]),
    ("universities", "fees", &[("government_standing", '-')]),
    ("universities", "merge", &[("exports", '-'), ("government_standing", '-')]),
    ("floods", "defend", &[("public_investment", '+'), ("government_standing", '+')]),
    ("floods", "councils", &[("government_standing", '-')]),
    ("net_zero_warning", "plan", &[("procurement", '+'), ("emission_intensity", '-'), ("government_standing", '+')]),
    ("net_zero_warning", "later", &[("government_standing", '-')]),
    ("net_zero_warning", "drop", &[("government_standing", '~')]),
    // Stage S13.7: two chance questions from 2028.
    ("fuel_protest", "cut", &[("fuel_duty_change", '-'), ("government_standing", '+')]),
    ("fuel_protest", "rebate", &[("subsidies", '+'), ("government_standing", '+')]),
    ("fuel_protest", "hold", &[("consumption", '-'), ("government_standing", '-')]),
    ("small_boats", "patrols", &[("procurement", '+'), ("government_standing", '+')]),
    ("small_boats", "offshore", &[("procurement", '+'), ("government_standing", '~')]),
    ("small_boats", "routes", &[("policy_migration_factor", '+'), ("government_standing", '~')]),
    // Stage S13.8: lenders refuse the gilts.
    ("gilt_crisis", "budget", &[("procurement", '-'), ("public_investment", '-'), ("government_standing", '-')]),
    ("gilt_crisis", "hold", &[("gilt_premium", '+'), ("inflation", '+'), ("government_standing", '-')]),
    ("gilt_crisis", "bank", &[("gilt_premium", '-'), ("inflation", '+'), ("government_standing", '-')]),
];

/// The seed of a run in which the dilemma opens, and the spending levers' factor from the
/// second month (1 for none).
fn recipe(dilemma: &str) -> (u64, i64) {
    match dilemma {
        "universities" | "water_company" => (8, 1),
        // A recession with unemployment above 5.5%: every public service cut by a third.
        "bank_rescue" => (2025, -3),
        // Stage S13.8: sustained heavy borrowing: every public service up by a third.
        "gilt_crisis" => (2025, 3),
        _ => (2025, 1),
    }
}

/// Every cell of a value after the last step, as reals.
fn cells(sim: &Simulation, name: &str) -> Vec<f64> {
    let real = |v: Val| match v {
        Val::I(x) => x as f64,
        Val::F(x) => x,
        Val::B(x) => x as u8 as f64,
    };
    if let Some(v) = sim.scalar(name) {
        return vec![real(v)];
    }
    match sim.column(name).unwrap_or_else(|| panic!("no value {name}")) {
        Col::I(v) => v.iter().map(|x| *x as f64).collect(),
        Col::F(v) => v.clone(),
        Col::B(v) => v.iter().map(|x| *x as u8 as f64).collect(),
    }
}

/// The run to the month the dilemma opens, saved there.
fn opened(model: &Arc<Model>, base: &RunConfig, dilemma: &str) -> Vec<u8> {
    let (seed, change) = recipe(dilemma);
    let mut config = base.clone();
    config.seed = seed;
    if change != 1 {
        config.commands = model
            .symbols
            .iter()
            .filter(|d| d.kind == Kind::Lever && d.name.starts_with("spending_"))
            .map(|d| {
                // A third off (-3) or on (3).
                let (num, den) = if change < 0 { (2, 3) } else { (4, 3) };
                let cut = match &d.spec["default"] {
                    Value::Integer(v) => Value::Integer(v * num / den),
                    other => Value::Float(other.as_float().unwrap() * num as f64 / den as f64),
                };
                (1, d.name.clone(), cut)
            })
            .collect();
    }
    let mut sim = Simulation::new(Arc::clone(model), config).unwrap();
    for _ in 0..60 {
        sim.step().unwrap();
        if sim.scalar(&format!("{dilemma}_open")) == Some(Val::B(true)) {
            return sim.save();
        }
    }
    panic!("{dilemma} did not open in five years with seed {seed}");
}

#[test]
fn every_answer_changes_what_it_says() {
    let scenario = load_scenario(&root().join("models/uk/scenarios/2025.toml")).unwrap();
    let model = Arc::new(scenario.model.clone());
    let base = scenario.config();
    // Every answer of every dilemma is in the table, in order.
    let answers: Vec<(String, String)> =
        model.dilemmas.iter().flat_map(|d| d.options.iter().map(move |o| (d.name.clone(), o.name.clone()))).collect();
    let listed: Vec<(String, String)> = EXPECT.iter().map(|(d, a, _)| (d.to_string(), a.to_string())).collect();
    assert_eq!(answers, listed, "the table lists every answer of every dilemma, in order");

    for dilemma in &model.dilemmas {
        let saved = opened(&model, &base, &dilemma.name);
        // Which dilemmas change each element, in order: the carriers the loader made.
        for (k, option) in dilemma.options.iter().enumerate() {
            let (_, _, changes) = EXPECT.iter().find(|(d, a, _)| *d == dilemma.name && *a == option.name).unwrap();
            let mut sim = Simulation::resume(Arc::clone(&model), &saved).unwrap();
            let at = sim.steps_done();
            sim.set_commands(vec![(at, dilemma.name.clone(), Value::Integer(k as i64 + 1))]);
            sim.step().unwrap();
            assert_eq!(sim.scalar(&format!("{}_choice", dilemma.name)), Some(Val::I(k as i64 + 1)));
            for (target, way) in *changes {
                let without = format!("{target}_before_{}", dilemma.name);
                let later = model
                    .dilemmas
                    .iter()
                    .skip_while(|d| d.name != dilemma.name)
                    .skip(1)
                    .map(|d| format!("{target}_before_{}", d.name))
                    .find(|n| model.sym_index.contains_key(n))
                    .unwrap_or_else(|| target.to_string());
                let (before, after) = (cells(&sim, &without), cells(&sim, &later));
                let shift: f64 = before.iter().zip(&after).map(|(b, a)| a - b).sum();
                let moved = before.iter().zip(&after).any(|(b, a)| a != b);
                let what = format!("{} answered {}: {target} {before:.6?} -> {after:.6?}", dilemma.name, option.name);
                match way {
                    '+' => assert!(shift > 0.0, "{what}: expected a rise"),
                    '-' => assert!(shift < 0.0, "{what}: expected a fall"),
                    _ => assert!(moved, "{what}: expected a change"),
                }
            }
        }
    }
}
