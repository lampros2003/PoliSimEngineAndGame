//! Times a game session's month (with tracing, history and cells, as the client runs it)
//! against the bare simulation's, and what the game client asks of it besides: a fork, a
//! twelve-month forecast (stage S14.3: and one sharing the "as is" branch), the full effects
//! table, a save and a load (with and without the effects table), and the bridge's mirror:
//! the whole copy made after every request before S14.3 against the update sent since, at
//! months 1, 60 and 120.
//!
//! cargo run --release --example session_time -- SCENARIO [STEPS] [EFFECT_THREADS]
use std::path::PathBuf;
use std::time::Instant;

use polisim_core::model::Kind;
use polisim_core::{Session, Val};

fn ms(started: Instant) -> f64 {
    started.elapsed().as_secs_f64() * 1e3
}

fn median(times: &mut [f64]) -> f64 {
    times.sort_by(f64::total_cmp);
    times[times.len() / 2]
}

/// What the bridge copied after every request before S14.3: latest and previous by row,
/// short cells, the changes and the whole history.
fn old_mirror(session: &Session) -> usize {
    let history = session.history().clone();
    let changes = session.changes().to_vec();
    month_maps(session) + history.steps.len() + changes.len()
}

/// Latest and previous by row, and short cells.
fn month_maps(session: &Session) -> usize {
    let catalogue = session.catalogue();
    let mut latest = std::collections::BTreeMap::<String, Val>::new();
    let mut previous = std::collections::BTreeMap::<String, Val>::new();
    let mut cells = std::collections::BTreeMap::new();
    for entry in catalogue.entries.iter().filter(|e| e.dims.len() == 1) {
        if let Some(now) = session.cells(&entry.name) {
            let before = session.previous_cells(&entry.name).map(<[f64]>::to_vec).unwrap_or_default();
            cells.insert(entry.name.clone(), (now.to_vec(), before));
        }
    }
    for entry in &catalogue.entries {
        let Some(row) = &entry.row else { continue };
        if let Some(v) = session.latest(row) {
            latest.insert(row.clone(), v);
        }
        if let Some(v) = session.previous(row) {
            previous.insert(row.clone(), v);
        }
    }
    latest.len() + previous.len() + cells.len()
}

/// What the bridge sends after a month since S14.3: the same maps, the month's history and
/// the month's changes. After any other request it sends only the changes waiting.
fn new_mirror(session: &Session) -> usize {
    let tail = session.history().tail(session.history().steps.len() - 1);
    month_maps(session) + tail.steps.len() + session.changes().len()
}

fn time_mirror(session: &Session, label: &str) {
    let reps = 20;
    let started = Instant::now();
    for _ in 0..reps {
        std::hint::black_box(old_mirror(session));
    }
    println!(
        "bridge mirror before S14.3 (whole copy, every request) at month {label}: {:.2} ms",
        ms(started) / reps as f64
    );
    let started = Instant::now();
    for _ in 0..reps {
        std::hint::black_box(new_mirror(session));
    }
    println!("bridge update after a month at month {label}: {:.2} ms", ms(started) / reps as f64);
    let started = Instant::now();
    for _ in 0..reps {
        std::hint::black_box(session.pending());
    }
    println!("bridge update after another request at month {label}: {:.3} ms", ms(started) / reps as f64);
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let path = PathBuf::from(args.first().expect("a scenario"));
    let steps: usize = args.get(1).map(|s| s.parse().unwrap()).unwrap_or(24);
    let threads: usize = args
        .get(2)
        .map(|s| s.parse().unwrap())
        .unwrap_or_else(|| std::thread::available_parallelism().map_or(1, |n| n.get()).saturating_sub(1).max(1));
    let started = Instant::now();
    let mut session = Session::open(&path).unwrap();
    println!("open: {:.0} ms", ms(started));
    session.step().unwrap();
    time_mirror(&session, "1");
    let mut times = Vec::new();
    for _ in 0..steps {
        let started = Instant::now();
        session.step().unwrap();
        times.push(ms(started));
    }
    println!("session: {:.2} ms a month (median)", median(&mut times));
    while session.steps_done() < 60 {
        session.step().unwrap();
    }
    time_mirror(&session, "60");
    while session.steps_done() < 120 {
        session.step().unwrap();
    }
    time_mirror(&session, "120");

    let started = Instant::now();
    let fork = session.fork().unwrap();
    println!("fork: {:.2} ms", ms(started));
    let mut times = Vec::new();
    for _ in 0..3 {
        let started = Instant::now();
        session.forecast(&[], 12).unwrap();
        times.push(ms(started));
    }
    println!("forecast, 12 months: {:.0} ms (best of 3)", times.iter().copied().fold(f64::INFINITY, f64::min));
    let levers: Vec<String> = session
        .catalogue()
        .entries
        .iter()
        .filter(|e| e.kind == Kind::Lever && e.player && e.dilemma.is_empty())
        .map(|e| e.name.clone())
        .collect();
    let started = Instant::now();
    let found = std::sync::Mutex::new(Vec::new());
    fork.effects(&levers, 12, threads, &|| false, &|e| found.lock().unwrap().push(e));
    let found = found.into_inner().unwrap();
    println!("effects table, {} levers x 12 months on {threads} threads: {:.0} ms", found.len(), ms(started));
    // Stage S14.3: a forecast once the effects table (or another forecast) has run the
    // "as is" branch, as the bridge shares it.
    let as_is = found.iter().find_map(|e| e.forecast.as_ref().ok()).map(|f| f.as_is.clone());
    let change = [(levers[0].clone(), fork.nudge(&levers[0]).unwrap().0)];
    let mut times = Vec::new();
    for _ in 0..3 {
        let started = Instant::now();
        session.fork().unwrap().forecast(as_is.clone(), &change, 12, &|| false).unwrap();
        times.push(ms(started));
    }
    println!(
        "forecast, 12 months, as-is shared: {:.0} ms (best of 3)",
        times.iter().copied().fold(f64::INFINITY, f64::min)
    );
    let started = Instant::now();
    let bytes = session.save();
    println!("save: {:.1} ms ({} kB)", ms(started), bytes.len() / 1024);
    let started = Instant::now();
    Session::load(&path, &bytes).unwrap();
    println!("load: {:.0} ms", ms(started));
    session.keep_effects(Some((12, found)));
    let started = Instant::now();
    let bytes = session.save();
    println!("save with the effects table: {:.1} ms ({} kB)", ms(started), bytes.len() / 1024);
    let started = Instant::now();
    Session::load(&path, &bytes).unwrap();
    println!("load with the effects table: {:.0} ms", ms(started));

    let scenario = polisim_core::load_scenario(&path).unwrap();
    let mut sim =
        polisim_core::Simulation::new(std::sync::Arc::new(scenario.model.clone()), scenario.config()).unwrap();
    let mut times = Vec::new();
    for _ in 0..steps {
        let started = Instant::now();
        sim.step().unwrap();
        times.push(ms(started));
    }
    println!("simulation: {:.2} ms a month (median)", median(&mut times));
    sim.set_tracing(true);
    let mut times = Vec::new();
    for _ in 0..steps {
        let started = Instant::now();
        sim.step().unwrap();
        times.push(ms(started));
    }
    println!("simulation, tracing: {:.2} ms a month (median)", median(&mut times));
    let started = Instant::now();
    for _ in 0..steps {
        std::hint::black_box(sim.state_hash());
    }
    println!("state hash: {:.2} ms", ms(started) / steps as f64);
}
