//! Times a scenario's month with and without tracing (a copy of the state per step):
//! cargo run --release --example trace_time -- SCENARIO [STEPS]
use std::time::Instant;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let path = std::path::PathBuf::from(&args[0]);
    let steps: usize = args.get(1).map(|s| s.parse().unwrap()).unwrap_or(24);
    let scenario = polisim_core::load_scenario(&path).unwrap();
    for tracing in [false, true, false, true] {
        let mut sim =
            polisim_core::Simulation::new(std::sync::Arc::new(scenario.model.clone()), scenario.config()).unwrap();
        sim.set_tracing(tracing);
        let started = Instant::now();
        for _ in 0..steps {
            sim.step().unwrap();
        }
        println!("tracing {tracing}: {:.2} ms a month", started.elapsed().as_secs_f64() * 1e3 / steps as f64);
    }
}
