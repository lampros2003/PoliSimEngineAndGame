//! The formula language's internals that tests/test_language.py does not reach through
//! `evaluate`: the marginal schedule on its own, and the exact random draw a formula makes
//! (moved here from the Python reference implementation's tests in stage S14.2).

use std::sync::Arc;

use polisim_core::rng::{fnv1a32, uniform};
use polisim_core::vm::marginal_amount;
use polisim_core::{Col, Computed, RunConfig, Simulation, Ty, load_model};

#[test]
fn marginal_schedule() {
    // 20% from 1,000 to 4,000 and 40% above, amounts in pence; the result is rounded
    // half to even, and thresholds out of order stop the run.
    let (lows, rates) = ([100_000, 400_000], [0.2, 0.4]);
    assert_eq!(marginal_amount(500_000, &lows, &rates), Ok(100_000));
    assert_eq!(marginal_amount(50_000, &lows, &rates), Ok(0));
    assert_eq!(marginal_amount(100_001, &lows, &rates), Ok(0));
    assert_eq!(marginal_amount(100_003, &lows, &rates), Ok(1));
    assert!(marginal_amount(1, &[400_000, 100_000], &rates).is_err());
}

const MODEL: &str = r#"
[model]
id = "draws"
format = 0
currency = "GBP"
minor_units = 1
step = "month"
phases = ["one"]

[entity.household]
data = "households.csv"
id = "id"
weight = "weight"

[stream.draws]
"#;

#[test]
fn a_draw_is_philox_of_seed_stream_record_and_step() {
    let dir = std::env::temp_dir().join(format!("polisim-language-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("model.toml"), MODEL).unwrap();
    std::fs::write(dir.join("households.csv"), "id,weight\n10,2\n11,3\n12,5\n").unwrap();
    let model = Arc::new(load_model(&dir).unwrap());
    std::fs::remove_dir_all(&dir).ok();
    let mut sim =
        Simulation::new(model, RunConfig { seed: 99, preset: "central".into(), ..Default::default() }).unwrap();
    let draw = |sim: &Simulation| match sim.evaluate("rand(draws)", Some("household"), Ty::Real, "1").unwrap() {
        Computed::Each(Col::F(v)) => v[1],
        other => panic!("{other:?}"),
    };
    assert_eq!(draw(&sim), uniform(99, fnv1a32("draws"), 11, 0));
    sim.step().unwrap();
    assert_eq!(draw(&sim), uniform(99, fnv1a32("draws"), 11, 1));
}
