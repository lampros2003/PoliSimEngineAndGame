//! Thirty years of unchanged policy in the UK model (models/uk). tests/test_uk.py covers
//! the first two years in detail, where the recorded hashes pin the run.
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
    // Thresholds rise with prices, but pay rises faster and, since S4.4, the households'
    // employment follows the economy's: income tax takes a slowly rising share of output
    // (fiscal drag), some 15% more after thirty years.
    let share = |r: &HashMap<String, f64>| r["income_tax"] / r["gdp"];
    let drift = share(last) / share(&rows[0]) - 1.0;
    assert!((0.0..0.3).contains(&drift), "income tax share of output drifted by {drift}");
}

/// Stage S4.4: raked each month, the households still match the cohort table after ten
/// years: people in households by region, sex and age band (the population times the base
/// year's share in households), households by type, and people in work by region (the
/// economy's employment, by each region's base share).
#[test]
fn after_ten_years_the_households_match_the_population() {
    use polisim_core::Col;
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let scenario = load_scenario(&root.join("models/uk/scenarios/2025.toml")).unwrap();
    let mut sim = Simulation::new(Arc::new(scenario.model.clone()), scenario.config()).unwrap();
    for _ in 0..120 {
        sim.step().unwrap();
    }
    let ints = |name: &str| match sim.column(name) {
        Some(Col::I(v)) => v.clone(),
        other => panic!("{name}: {other:?}"),
    };
    let reals = |name: &str| match sim.column(name) {
        Some(Col::F(v)) => v.clone(),
        other => panic!("{name}: {other:?}"),
    };
    let (w, region, kind, adults) = (ints("household_weight"), ints("region_code"), ints("type"), ints("adults"));
    let band = |age: i64| [15, 24, 34, 49, 64, 74, 90].iter().position(|top| age <= *top).unwrap();
    let mut people = vec![0.0f64; 12 * 2 * 7];
    let mut types = vec![0.0f64; 10];
    let mut workers = vec![0.0f64; 12];
    let sexes: Vec<Vec<i64>> = (1..=4).map(|i| ints(&format!("sex{i}"))).collect();
    let ages: Vec<Vec<i64>> = (1..=4).map(|i| ints(&format!("age{i}"))).collect();
    let earnings: Vec<Vec<i64>> = (1..=4).map(|i| ints(&format!("earnings{i}"))).collect();
    let children = [("girls", 0, 0), ("boys", 1, 0), ("older_girls", 0, 1), ("older_boys", 1, 1)]
        .map(|(name, sex, b)| (ints(name), sex as usize, b));
    for r in 0..w.len() {
        let weight = w[r] as f64;
        types[kind[r] as usize] += weight;
        let cell = |sex: usize, b: usize| (region[r] as usize * 2 + sex) * 7 + b;
        for i in 0..adults[r] as usize {
            people[cell(sexes[i][r] as usize, band(ages[i][r]))] += weight;
            if earnings[i][r] > 0 {
                workers[region[r] as usize] += weight;
            }
        }
        for (column, sex, b) in &children {
            people[cell(*sex, *b)] += weight * column[r] as f64;
        }
    }
    let worst = |got: &[f64], want: &[f64]| {
        got.iter().zip(want).filter(|(_, t)| **t > 0.0).map(|(g, t)| (g / t - 1.0).abs()).fold(0.0, f64::max)
    };
    let people_error = worst(&people, &reals("people_in_households_target"));
    let type_error = worst(&types, &reals("households_by_type_target"));
    let worker_error = worst(&workers, &reals("workers_target"));
    assert!(people_error < 0.005, "people by region, sex and age band off by {people_error}");
    assert!(type_error < 0.005, "households by type off by {type_error}");
    assert!(worker_error < 0.0001, "people in work by region off by {worker_error}");
    // The targets are the cohort table's, and it has moved in ten years: weights have too.
    let base: f64 = sim.model().entities[0].weights.iter().map(|w| *w as f64).sum();
    let now: f64 = w.iter().map(|w| *w as f64).sum();
    assert!((now / base - 1.0).abs() > 0.02, "households {now} against {base} at the start");
    eprintln!("after 120 months: people {people_error:.5}, types {type_error:.5}, workers {worker_error:.7}");
}
