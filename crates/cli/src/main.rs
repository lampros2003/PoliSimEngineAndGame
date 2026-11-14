//! Command-line runner. Its CSV is byte for byte the Python oracle's:
//!
//! ```text
//! polisim run models/toy/scenarios/baseline.toml --out run.csv
//! ```
//!
//! Money columns are whole numbers of minor units (pence), so the file is exact.
//! Exit codes: 0 finished, 1 the model or scenario could not be loaded, 2 the run failed
//! part-way (the rows completed before the failure are still written).

mod play;

use std::io::Write;
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Instant;

use polisim_core::{Error, Row, Simulation, Val, load_scenario, pyfmt};

const USAGE: &str = "\
usage: polisim run <scenario.toml> [options]
       polisim play <scenario.toml> [--seed N] [--resume FILE]
       polisim text <scenario.toml> [LANGUAGE]
       polisim version

options:
  --out FILE       write the CSV to FILE instead of standard output
  --steps N        number of steps to run (default: the scenario's)
  --seed N         random seed (default: the scenario's)
  --columns A,B,C  write only these columns
  --save FILE      write a save file after the last step
  --resume FILE    continue from a save file; seed and parameters come from the save
  --time           report milliseconds per step on standard error
  --profile N      report the N formulas that took longest, per step, on standard error

polisim text lists the languages a scenario's model and mods have text in, or, given one,
what the model has words for that the language does not translate (exit 1 if anything).";

#[derive(Default)]
struct Options {
    scenario: Option<PathBuf>,
    out: Option<PathBuf>,
    steps: Option<u64>,
    seed: Option<u64>,
    columns: Option<Vec<String>>,
    save: Option<PathBuf>,
    resume: Option<PathBuf>,
    time: bool,
    /// Stage S10: print the N formulas that took longest.
    profile: Option<usize>,
}

fn parse_options(args: &[String]) -> Result<Options, String> {
    let mut options = Options::default();
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        let mut value = |name: &str| iter.next().cloned().ok_or_else(|| format!("{name} needs a value"));
        match arg.as_str() {
            "--out" => options.out = Some(value("--out")?.into()),
            "--steps" => options.steps = Some(value("--steps")?.parse().map_err(|_| "--steps needs a whole number")?),
            "--seed" => {
                // Any whole number; it is reduced to 64 bits as the oracle does.
                let seed: i128 = value("--seed")?.parse().map_err(|_| "--seed needs a whole number")?;
                options.seed = Some(seed as u64);
            }
            "--columns" => options.columns = Some(value("--columns")?.split(',').map(str::to_string).collect()),
            "--save" => options.save = Some(value("--save")?.into()),
            "--resume" => options.resume = Some(value("--resume")?.into()),
            "--time" => options.time = true,
            "--profile" => {
                options.profile = Some(value("--profile")?.parse().map_err(|_| "--profile needs a whole number")?)
            }
            other if other.starts_with("--") => return Err(format!("unknown option {other}")),
            other if options.scenario.is_none() => options.scenario = Some(other.into()),
            other => return Err(format!("unexpected argument {other}")),
        }
    }
    Ok(options)
}

fn cell(value: &Val) -> String {
    match value {
        Val::I(v) => v.to_string(),
        Val::F(v) => pyfmt::float_repr(*v),
        Val::B(v) => pyfmt::bool_str(*v).to_string(),
    }
}

fn write_csv(out: &mut dyn Write, names: &[String], rows: &[Row], columns: Option<&[String]>) -> std::io::Result<()> {
    if rows.is_empty() {
        return Ok(());
    }
    let all: Vec<String> = ["step", "hash"].iter().map(|s| s.to_string()).chain(names.iter().cloned()).collect();
    let chosen: &[String] = columns.unwrap_or(&all);
    // A requested column that does not exist is written empty, as the oracle writes it.
    let positions: Vec<Option<usize>> = chosen.iter().map(|c| all.iter().position(|n| n == c)).collect();
    writeln!(out, "{}", chosen.join(","))?;
    for row in rows {
        let line: Vec<String> = positions
            .iter()
            .map(|position| match position {
                Some(0) => row.step.to_string(),
                Some(1) => pyfmt::hex(&row.hash),
                Some(index) => cell(&row.values[index - 2]),
                None => String::new(),
            })
            .collect();
        writeln!(out, "{}", line.join(","))?;
    }
    Ok(())
}

fn run(options: Options) -> Result<ExitCode, String> {
    let Some(path) = &options.scenario else { return Err(USAGE.to_string()) };
    let scenario = load_scenario(path).map_err(|e| e.to_string())?;
    let model = Arc::new(scenario.model.clone());
    let mut sim = match &options.resume {
        Some(file) => {
            if options.seed.is_some() {
                return Err("--seed cannot be combined with --resume: the seed comes from the save".to_string());
            }
            let bytes = std::fs::read(file).map_err(|e| format!("cannot read {}: {e}", file.display()))?;
            let mut sim = Simulation::resume(Arc::clone(&model), &bytes).map_err(|e| e.to_string())?;
            sim.set_commands(scenario.commands.clone());
            sim
        }
        None => {
            let mut config = scenario.config();
            if let Some(seed) = options.seed {
                config.seed = seed;
            }
            Simulation::new(Arc::clone(&model), config).map_err(|e| e.to_string())?
        }
    };

    if options.profile.is_some() {
        sim.set_profiling(true);
    }
    let steps = options.steps.unwrap_or(scenario.steps);
    let mut rows = Vec::with_capacity(steps as usize);
    let mut failure = None;
    let started = Instant::now();
    for _ in 0..steps {
        match sim.step() {
            Ok(row) => rows.push(row),
            Err(Error::Sim(message)) => {
                failure = Some(message);
                break;
            }
            Err(other) => return Err(other.to_string()),
        }
    }
    let elapsed = started.elapsed();

    let io_error = |e: std::io::Error| format!("cannot write output: {e}");
    let columns = options.columns.as_deref();
    match &options.out {
        Some(file) => {
            let mut buffer = Vec::new();
            write_csv(&mut buffer, sim.row_names(), &rows, columns).map_err(io_error)?;
            std::fs::write(file, buffer).map_err(|e| format!("cannot write {}: {e}", file.display()))?;
        }
        None => {
            let stdout = std::io::stdout();
            write_csv(&mut stdout.lock(), sim.row_names(), &rows, columns).map_err(io_error)?;
        }
    }
    if let Some(message) = failure {
        eprintln!("error: {message}");
        return Ok(ExitCode::from(2));
    }
    if let Some(file) = &options.save {
        std::fs::write(file, sim.save()).map_err(|e| format!("cannot write {}: {e}", file.display()))?;
    }
    if options.out.is_some() {
        let model_hash = &sim.model().model_hash_hex()[..12];
        match rows.last() {
            Some(last) => {
                eprintln!(
                    "{}: {} steps, model {model_hash}, final state {}",
                    scenario.name,
                    rows.len(),
                    &pyfmt::hex(&last.hash)[..12]
                )
            }
            None => eprintln!("{}: 0 steps, model {model_hash}", scenario.name),
        }
    }
    if options.time && !rows.is_empty() {
        let steps = rows.len() as f64;
        eprintln!("{:.3} ms per step over {} steps", elapsed.as_secs_f64() * 1e3 / steps, rows.len());
        for (phase, spent) in sim.phase_times() {
            eprintln!("  {phase:<12} {:>9.3} ms per step", spent.as_secs_f64() * 1e3 / steps);
        }
    }
    if let (Some(top), false) = (options.profile, rows.is_empty()) {
        let steps = rows.len() as f64;
        let times = sim.symbol_times();
        let total: f64 = times.iter().map(|(_, t, _)| t.as_secs_f64()).sum();
        eprintln!("formulas, slowest first ({:.3} ms per step in all):", total * 1e3 / steps);
        for (name, spent, _) in times.iter().take(top) {
            let d = sim.model().sym(name).expect("a symbol");
            let phase = d.phase.map(|p| sim.model().phases[p].as_str()).unwrap_or("");
            eprintln!(
                "  {name:<36} {:>8.3} ms {:>5.1}%  {} {phase}",
                spent.as_secs_f64() * 1e3 / steps,
                spent.as_secs_f64() / total * 100.0,
                d.kind.name()
            );
        }
    }
    Ok(ExitCode::SUCCESS)
}

fn play_session(options: Options) -> Result<(), String> {
    let Some(path) = &options.scenario else { return Err(USAGE.to_string()) };
    let scenario = load_scenario(path).map_err(|e| e.to_string())?;
    let resume = match &options.resume {
        Some(file) => Some(std::fs::read(file).map_err(|e| format!("cannot read {}: {e}", file.display()))?),
        None => None,
    };
    play::play(scenario, options.seed, resume)
}

/// Stage S7.4: the languages a model has text in, or what one of them leaves out.
fn text_check(args: &[String]) -> Result<ExitCode, String> {
    let Some(path) = args.first() else { return Err(USAGE.to_string()) };
    let scenario = load_scenario(&PathBuf::from(path)).map_err(|e| e.to_string())?;
    let model = &scenario.model;
    let Some(language) = args.get(1) else {
        for (code, name) in polisim_core::languages(model) {
            println!("{code}\t{name}");
        }
        return Ok(ExitCode::SUCCESS);
    };
    let Some(text) = polisim_core::load_text(model, language).map_err(|e| e.to_string())? else {
        return Err(format!("{} has no text in {language:?}", model.id));
    };
    let missing = text.missing(model);
    for key in &missing {
        println!("{key}");
    }
    eprintln!("{}: {} untranslated", text.name, missing.len());
    Ok(if missing.is_empty() { ExitCode::SUCCESS } else { ExitCode::from(1) })
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let outcome = match args.first().map(String::as_str) {
        Some("run") => parse_options(&args[1..]).and_then(run),
        Some("play") => parse_options(&args[1..]).and_then(play_session).map(|()| ExitCode::SUCCESS),
        Some("text") => text_check(&args[1..]),
        Some("version") => {
            println!("polisim {}", polisim_core::VERSION);
            Ok(ExitCode::SUCCESS)
        }
        _ => Err(USAGE.to_string()),
    };
    match outcome {
        Ok(code) => code,
        Err(message) => {
            eprintln!("error: {message}");
            ExitCode::from(1)
        }
    }
}
