//! Thirty years of unchanged policy in the UK model (models/uk), on the engine. The oracle's
//! tests (oracle/tests/test_uk.py) cover the first two years, where the recorded hashes tie
//! the engine to the oracle; with 20,000 households the oracle is too slow for 360 months.
//! Ranges are wide on purpose: they catch a model that breaks, not one slightly off.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use polisim_core::{Simulation, Val, load_scenario};

fn run(months: usize) -> Vec<HashMap<String, f64>> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let scenario = load_scenario(&root.join("models/uk/scenarios/2025.toml")).unwrap();
    let mut sim = Simulation::new(Arc::new(scenario.model.clone()), scenario.config()).unwrap();
    let names: Vec<String> = sim.row_names().to_vec();
    (0..months)
        .map(|_| {
            let row = sim.step().unwrap();
            names
                .iter()
                .zip(&row.values)
                .map(|(n, v)| {
                    let x = match v {
                        Val::I(i) => *i as f64,
                        Val::F(f) => *f,
                        Val::B(b) => *b as i64 as f64,
                    };
                    (n.clone(), x)
                })
                .collect()
        })
        .collect()
}

#[test]
fn thirty_years_of_unchanged_policy_stay_in_range() {
    let rows = run(360);
    for (t, row) in rows.iter().enumerate() {
        let u = row["unemployment_rate"];
        assert!((0.03..0.07).contains(&u), "unemployment {u} in month {t}");
        if t >= 12 {
            let i = row["inflation_annual"];
            assert!((0.0..0.04).contains(&i), "inflation {i} in month {t}");
        }
        for money in ["household_money", "firm_money", "foreign_money"] {
            assert!(row[money] > 0.0, "{money} in month {t}");
        }
        // Known weakness of version 0: no fiscal rule, so debt drifts up (models/uk/README.md).
        assert!(row["debt_to_gdp"] < 2.0, "debt in month {t}");
    }
    let year = |from: usize| rows[from..from + 12].iter().map(|r| r["real_gdp"]).sum::<f64>();
    let growth = (year(348) / year(0)).powf(1.0 / 29.0) - 1.0;
    assert!((0.01..0.025).contains(&growth), "real growth {growth}");
    let last = &rows[359];
    assert!((70e6..95e6).contains(&last["population_total"]), "population {}", last["population_total"]);
    let old = last["pension_age_population"] / last["population_total"];
    assert!((0.17..0.35).contains(&old), "share aged 66 and over {old}");
    // Thresholds rise with prices, so income tax keeps roughly its share of output.
    let share = |r: &HashMap<String, f64>| r["income_tax"] / r["gdp"];
    assert!((share(last) / share(&rows[0]) - 1.0).abs() < 0.15, "income tax share of output drifted");
}
