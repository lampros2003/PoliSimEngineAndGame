//! Times a game session's month (with tracing, history and cells, as the client runs it)
//! against the bare simulation's: cargo run --release --example session_time -- SCENARIO [STEPS]
use std::path::PathBuf;
use std::time::Instant;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let path = PathBuf::from(args.first().expect("a scenario"));
    let steps: usize = args.get(1).map(|s| s.parse().unwrap()).unwrap_or(24);
    let started = Instant::now();
    let mut session = polisim_core::Session::open(&path).unwrap();
    println!("open: {:.0} ms", started.elapsed().as_secs_f64() * 1e3);
    let started = Instant::now();
    for _ in 0..steps {
        session.step().unwrap();
    }
    println!("session: {:.2} ms a month", started.elapsed().as_secs_f64() * 1e3 / steps as f64);
    let scenario = polisim_core::load_scenario(&path).unwrap();
    let mut sim =
        polisim_core::Simulation::new(std::sync::Arc::new(scenario.model.clone()), scenario.config()).unwrap();
    let started = Instant::now();
    for _ in 0..steps {
        sim.step().unwrap();
    }
    println!("simulation: {:.2} ms a month", started.elapsed().as_secs_f64() * 1e3 / steps as f64);
}
