//! Interactive session: set levers, advance time, look at the results.

use std::io::{BufRead, Write};
use std::sync::Arc;

use polisim_core::model::Kind;
use polisim_core::{Error, RawValue, Row, Scenario, Simulation, Val, units};

const HELP: &str = "\
commands:
  step [N]            advance N steps (default 1); an empty line does the same
  set LEVER VALUE     change a policy lever from the next step on
  levers              list the levers, their settings and their limits
  show [NAME ...]     show values from the last step (default: the watch list)
  watch NAME ...      choose what is shown after each step
  names               list everything that can be shown
  save FILE           write a save file
  help                this text
  quit                end the session";

fn group_thousands(digits: &str) -> String {
    let mut out = String::new();
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i) % 3 == 0 {
            out.push(',');
        }
        out.push(c);
    }
    out
}

/// A value for people: money in major units with separators, reals to four places.
fn display(value: &Val, money: bool, minor: i64) -> String {
    match value {
        Val::I(v) if money && minor > 1 => {
            let (sign, magnitude) = (if *v < 0 { "-" } else { "" }, v.unsigned_abs());
            let places = (minor as f64).log10().round() as usize;
            let (whole, part) = (magnitude / minor as u64, magnitude % minor as u64);
            format!("{sign}{}.{part:0places$}", group_thousands(&whole.to_string()))
        }
        Val::I(v) => {
            let sign = if *v < 0 { "-" } else { "" };
            format!("{sign}{}", group_thousands(&v.unsigned_abs().to_string()))
        }
        Val::F(v) => format!("{v:.4}"),
        Val::B(v) => v.to_string(),
    }
}

fn parse_value(text: &str) -> Option<RawValue> {
    let plain = text.replace(['_', ','], "");
    match plain.as_str() {
        "true" => Some(RawValue::Boolean(true)),
        "false" => Some(RawValue::Boolean(false)),
        _ => {
            plain.parse::<i64>().map(RawValue::Integer).ok().or_else(|| plain.parse::<f64>().map(RawValue::Float).ok())
        }
    }
}

struct Session {
    sim: Simulation,
    scenario: Scenario,
    commands: Vec<(u64, String, RawValue)>,
    watch: Vec<String>,
    last: Option<Row>,
}

impl Session {
    /// Description of a row column: (is money, unit text).
    fn describe(&self, name: &str) -> (bool, String) {
        let symbol = name.strip_suffix(".total").unwrap_or(name);
        match self.sim.model().sym(symbol) {
            Some(d) => {
                let mut unit = Some(d.unit.clone());
                if name.ends_with(".total") {
                    // A sector total: the per-record unit times the number of records' units.
                    let entity = d.entity.map(|e| self.sim.model().entities[e].name.as_str());
                    unit = entity.map(|e| units::mul(&unit, &Some(units::Unit::base(e))));
                }
                (d.money, units::fmt(&unit))
            }
            None => (false, String::new()),
        }
    }

    fn show(&self, names: &[String]) {
        let Some(row) = &self.last else {
            println!("nothing to show yet: no step has run");
            return;
        };
        let width = names.iter().map(String::len).max().unwrap_or(0);
        for name in names {
            match self.sim.row_names().iter().position(|n| n == name) {
                Some(index) => {
                    let (money, unit) = self.describe(name);
                    let unit = if unit == "1" { String::new() } else { unit };
                    println!(
                        "  {name:<width$}  {:>22}  {unit}",
                        display(&row.values[index], money, self.sim.model().minor)
                    );
                }
                None => println!("  {name:<width$}  (no such value; try `names`)"),
            }
        }
    }

    fn levers(&self) {
        let model = self.sim.model();
        for d in model.symbols.iter().filter(|d| d.kind == Kind::Lever) {
            let current = self.sim.scalar(&d.name).expect("levers are national values");
            let scale = if d.money { model.minor as f64 } else { 1.0 };
            let limits = match d.range {
                Some((lo, hi)) => format!("{} to {}", lo / scale, hi / scale),
                None => "no limits".to_string(),
            };
            let pending =
                self.commands.iter().rev().find(|(step, lever, _)| *step == self.sim.steps_done() && *lever == d.name);
            let pending = match pending.and_then(|(_, _, raw)| self.sim.check_lever(&d.name, raw).ok()) {
                Some(value) => format!("  -> {} next step", display(&value, d.money, model.minor)),
                None => String::new(),
            };
            let doc = d.spec.get("doc").and_then(|v| v.as_str()).unwrap_or("");
            println!(
                "  {:<20} {:>18}  [{limits}] {}{pending}",
                d.name,
                display(&current, d.money, model.minor),
                Some(units::fmt(&Some(d.unit.clone()))).filter(|u| u != "1").unwrap_or_default()
            );
            if !doc.is_empty() {
                println!("  {:<20} {doc}", "");
            }
        }
    }

    /// Advances `count` steps. Returns false when the run has failed and must end.
    fn step(&mut self, count: u64) -> bool {
        for _ in 0..count {
            match self.sim.step() {
                Ok(row) => self.last = Some(row),
                Err(error) => {
                    println!("the run has failed and cannot continue: {error}");
                    return false;
                }
            }
        }
        println!("after step {} ({} completed):", self.sim.steps_done() - 1, self.sim.steps_done());
        self.show(&self.watch.clone());
        true
    }

    fn set(&mut self, lever: &str, text: &str) {
        let Some(raw) = parse_value(text) else {
            println!("{text:?} is not a number or true/false");
            return;
        };
        match self.sim.check_lever(lever, &raw) {
            Ok(value) => {
                let d = self.sim.model().sym(lever).expect("checked");
                println!("{lever} will be {} from the next step", display(&value, d.money, self.sim.model().minor));
                self.commands.push((self.sim.steps_done(), lever.to_string(), raw));
                self.sim.set_commands(self.commands.clone());
            }
            Err(error) => println!("not changed: {error}"),
        }
    }
}

pub fn play(scenario: Scenario, seed: Option<u64>, resume: Option<Vec<u8>>) -> Result<(), String> {
    let model = Arc::new(scenario.model.clone());
    let sim = match resume {
        Some(bytes) => Simulation::resume(Arc::clone(&model), &bytes),
        None => {
            let mut config = scenario.config();
            if let Some(seed) = seed {
                config.seed = seed;
            }
            Simulation::new(Arc::clone(&model), config)
        }
    }
    .map_err(|e: Error| e.to_string())?;

    let mut watch = scenario.watch.clone();
    if watch.is_empty() {
        watch = sim.row_names().iter().take(8).cloned().collect();
    }
    let commands = scenario.commands.clone();
    let mut session = Session { sim, scenario, commands, watch, last: None };
    session.sim.set_commands(session.commands.clone());

    println!(
        "{} — one step is one {}. Type `help` for commands.",
        session.scenario.name,
        units::fmt(&Some(model.step_unit.clone()))
    );
    session.levers();
    let stdin = std::io::stdin();
    loop {
        print!("[{}] > ", session.sim.steps_done());
        std::io::stdout().flush().ok();
        let mut line = String::new();
        if stdin.lock().read_line(&mut line).map_err(|e| e.to_string())? == 0 {
            println!();
            return Ok(());
        }
        let words: Vec<&str> = line.split_whitespace().collect();
        match words.as_slice() {
            [] | ["step"] | ["s"] => {
                if !session.step(1) {
                    return Ok(());
                }
            }
            ["step" | "s", count] => match count.parse::<u64>() {
                Ok(count) if count <= 10_000 => {
                    if !session.step(count) {
                        return Ok(());
                    }
                }
                _ => println!("step takes a whole number up to 10,000"),
            },
            ["set", lever, value] => session.set(lever, value),
            ["levers"] => session.levers(),
            ["show"] => session.show(&session.watch.clone()),
            ["show", names @ ..] => session.show(&names.iter().map(|n| n.to_string()).collect::<Vec<_>>()),
            ["watch", names @ ..] if !names.is_empty() => session.watch = names.iter().map(|n| n.to_string()).collect(),
            ["names"] => println!("  {}", session.sim.row_names().join("\n  ")),
            ["save", file] => match std::fs::write(file, session.sim.save()) {
                Ok(()) => println!("saved to {file}"),
                Err(error) => println!("could not save: {error}"),
            },
            ["help" | "?"] => println!("{HELP}"),
            ["quit" | "exit" | "q"] => return Ok(()),
            _ => println!("not understood; type `help`"),
        }
    }
}
