//! Times loading a scenario and building its simulation:
//! cargo run --release --example load_time -- SCENARIO
use std::time::Instant;

fn main() {
    let path = std::path::PathBuf::from(std::env::args().nth(1).expect("a scenario"));
    let started = Instant::now();
    let scenario = polisim_core::load_scenario(&path).unwrap();
    let loaded = started.elapsed();
    let started = Instant::now();
    let model = std::sync::Arc::new(scenario.model.clone());
    let cloned = started.elapsed();
    let started = Instant::now();
    let sim = polisim_core::Simulation::new(model, scenario.config()).unwrap();
    let built = started.elapsed();
    let started = Instant::now();
    drop(sim);
    drop(scenario);
    let dropped = started.elapsed();
    let ms = |d: std::time::Duration| d.as_secs_f64() * 1e3;
    println!(
        "load {:.0} ms, clone {:.0} ms, build {:.0} ms, drop {:.0} ms",
        ms(loaded),
        ms(cloned),
        ms(built),
        ms(dropped)
    );
}
