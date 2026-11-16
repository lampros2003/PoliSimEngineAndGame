//! `polisim serve`: runs of one model driven line by line on standard input, answered in
//! JSON on standard output, for tests and tools (docs/spec/09-serve.md).

use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::Arc;

use polisim_core::{
    Computed, Error, Model, RawTable, RawValue, RunConfig, Scenario, Simulation, Ty, load_model_with_mods,
    load_scenario_with_mods, pyfmt, units,
};

use crate::json::Json;

/// What a session serves: the model, the scenario it came from (if any) and its runs. Run
/// 0 starts with the session; `open` adds more, `close` frees one.
pub struct Server {
    model: Arc<Model>,
    scenario: Option<Scenario>,
    runs: Vec<Option<Result<Simulation, Error>>>,
    /// The run the request being answered is about.
    current: usize,
}

fn error(kind: &str, message: &str) -> Json {
    Json::obj(vec![("error", Json::str(message)), ("kind", Json::str(kind))])
}

fn engine_error(e: &Error) -> Json {
    let kind = match e {
        Error::Model(_) => "model",
        Error::Formula(_) => "formula",
        Error::Sim(_) => "run",
    };
    error(kind, e.message())
}

fn ok(fields: Vec<(&str, Json)>) -> Json {
    let mut all = vec![("ok", Json::Bool(true))];
    all.extend(fields);
    Json::obj(all)
}

/// A TOML value written on its own: `0.25`, `"low"`, `{seed = 3}`.
fn toml_value(text: &str) -> Result<RawValue, String> {
    let mut table: RawTable = format!("v = {text}").parse().map_err(|e| format!("not a TOML value: {text}: {e}"))?;
    table.remove("v").ok_or_else(|| format!("not a TOML value: {text}"))
}

fn ty(name: &str) -> Result<Ty, String> {
    match name {
        "int" => Ok(Ty::Int),
        "real" => Ok(Ty::Real),
        "bool" => Ok(Ty::Bool),
        other => Err(format!("type must be int, real or bool, not {other:?}")),
    }
}

fn computed(value: Computed) -> Json {
    match value {
        Computed::One(v) => v.into(),
        Computed::Each(column) => (&column).into(),
    }
}

fn pairs(list: &[(String, RawValue)]) -> Json {
    Json::Obj(list.iter().map(|(k, v)| (k.clone(), v.into())).collect())
}

impl Server {
    /// Loads a scenario file or a model folder, with extra mods, and starts its run.
    pub fn open(path: &Path, mods: &[PathBuf], seed: Option<u64>, preset: Option<&str>) -> Result<Server, Error> {
        let (model, scenario, mut config) = if path.is_file() {
            let scenario = load_scenario_with_mods(path, mods)?;
            let config = scenario.config();
            (scenario.model.clone(), Some(scenario), config)
        } else {
            let config = RunConfig { preset: "central".into(), ..Default::default() };
            (load_model_with_mods(path, mods)?, None, config)
        };
        if let Some(seed) = seed {
            config.seed = seed;
        }
        if let Some(preset) = preset {
            config.preset = preset.to_string();
        }
        let model = Arc::new(model);
        let sim = Simulation::new(Arc::clone(&model), config);
        Ok(Server { model, scenario, runs: vec![Some(sim)], current: 0 })
    }

    /// The first line: the model loaded.
    pub fn hello(&self) -> Json {
        ok(vec![("model", Json::str(&self.model.id)), ("model_hash", Json::Str(self.model.model_hash_hex()))])
    }

    /// One request, one reply. `None` ends the session. `@N request` is about run N; a
    /// request without it is about run 0.
    pub fn handle(&mut self, line: &str) -> Option<Json> {
        let mut line = line.trim();
        self.current = 0;
        if let Some(addressed) = line.strip_prefix('@') {
            let (id, rest) = addressed.split_once(char::is_whitespace).unwrap_or((addressed, ""));
            match id.parse() {
                Ok(id) => self.current = id,
                Err(_) => return Some(error("request", &format!("@{id}: not a run number"))),
            }
            line = rest.trim();
        }
        let (verb, rest) = line.split_once(char::is_whitespace).map_or((line, ""), |(v, r)| (v, r.trim()));
        let reply = match verb {
            "quit" => return None,
            "open" => self.open_run(rest),
            "close" => self.close_run(),
            "new" => self.new_run(rest),
            "set" => self.set(rest),
            "step" => self.step(rest),
            "get" => self.get(rest),
            "evaluate" => self.evaluate(rest),
            "votes" => self.votes(),
            "model" => Ok(self.describe()),
            "symbols" => Ok(self.symbols()),
            "scenario" => self.scenario(),
            "" => Err(error("request", "empty request")),
            other => Err(error("request", &format!("unknown request {other:?}"))),
        };
        Some(reply.unwrap_or_else(|e| e))
    }

    /// The addressed run, which may hold the error it could not start with.
    fn exists(&mut self) -> Result<&mut Result<Simulation, Error>, Json> {
        let current = self.current;
        match self.runs.get_mut(current) {
            Some(Some(run)) => Ok(run),
            _ => Err(error("request", &format!("no run {current}"))),
        }
    }

    /// The addressed run; until it has started, every request about it repeats why not.
    fn sim(&mut self) -> Result<&mut Simulation, Json> {
        self.exists()?.as_mut().map_err(|e| engine_error(e))
    }

    /// The settings of a new run: `{seed = 1, preset = "central", params = {..}, levers = {..}}`,
    /// each optional (seed 0, the central preset, the model's own values).
    fn config(rest: &str) -> Result<RunConfig, Json> {
        let mut config = RunConfig { preset: "central".into(), ..Default::default() };
        if rest.is_empty() {
            return Ok(config);
        }
        let RawValue::Table(table) = toml_value(rest).map_err(|e| error("request", &e))? else {
            return Err(error("request", "a run's settings are a table: {seed = 1, preset = \"central\", ...}"));
        };
        for (key, value) in table {
            match (key.as_str(), value) {
                // Any whole number, reduced to 64 bits as `polisim run --seed` does.
                ("seed", RawValue::Integer(seed)) => config.seed = seed as u64,
                ("preset", RawValue::String(preset)) => config.preset = preset,
                ("params", RawValue::Table(t)) => config.params = t.into_iter().collect(),
                ("levers", RawValue::Table(t)) => config.levers = t.into_iter().collect(),
                (key, _) => return Err(error("request", &format!("unexpected setting {key}"))),
            }
        }
        Ok(config)
    }

    /// Starts the addressed run again with new settings.
    fn new_run(&mut self, rest: &str) -> Result<Json, Json> {
        let config = Self::config(rest)?;
        self.exists()?;
        let sim = Simulation::new(Arc::clone(&self.model), config);
        self.runs[self.current] = Some(sim);
        self.sim()?;
        Ok(ok(vec![]))
    }

    /// Starts another run; its number comes back. One that cannot start is not kept.
    fn open_run(&mut self, rest: &str) -> Result<Json, Json> {
        let sim = Simulation::new(Arc::clone(&self.model), Self::config(rest)?).map_err(|e| engine_error(&e))?;
        let id = match self.runs.iter().position(Option::is_none) {
            Some(free) => free,
            None => {
                self.runs.push(None);
                self.runs.len() - 1
            }
        };
        self.runs[id] = Some(Ok(sim));
        Ok(ok(vec![("run", Json::Int(id as i128))]))
    }

    fn close_run(&mut self) -> Result<Json, Json> {
        self.exists()?;
        self.runs[self.current] = None;
        Ok(ok(vec![]))
    }

    /// A lever change, or the answer to a dilemma, for the next step.
    fn set(&mut self, rest: &str) -> Result<Json, Json> {
        let Some((name, value)) = rest.split_once(char::is_whitespace) else {
            return Err(error("request", "set takes a name and a value"));
        };
        let value = toml_value(value.trim()).map_err(|e| error("request", &e))?;
        let sim = self.sim()?;
        let mut commands = sim.commands();
        commands.push((sim.steps_done(), name.to_string(), value));
        sim.set_commands(commands);
        Ok(ok(vec![]))
    }

    fn step(&mut self, rest: &str) -> Result<Json, Json> {
        let count: u64 =
            if rest.is_empty() { 1 } else { rest.parse().map_err(|_| error("request", "step takes a count"))? };
        let sim = self.sim()?;
        let names = sim.row_names().to_vec();
        let mut rows = Vec::new();
        for _ in 0..count {
            match sim.step() {
                Ok(row) => {
                    let mut fields = vec![
                        ("step".to_string(), Json::Int(row.step as i128)),
                        ("hash".to_string(), Json::Str(pyfmt::hex(&row.hash))),
                    ];
                    fields.extend(names.iter().cloned().zip(row.values.iter().map(|v| Json::from(*v))));
                    rows.push(Json::Obj(fields));
                }
                Err(e) => {
                    let Json::Obj(mut fields) = engine_error(&e) else { unreachable!() };
                    fields.push(("rows".to_string(), Json::Arr(rows)));
                    return Err(Json::Obj(fields));
                }
            }
        }
        Ok(ok(vec![("rows", Json::Arr(rows))]))
    }

    fn get(&mut self, name: &str) -> Result<Json, Json> {
        let sim = self.sim()?;
        let value = match (sim.column(name), sim.scalar(name)) {
            (Some(column), _) => column.into(),
            (None, Some(value)) => value.into(),
            (None, None) => return Err(error("request", &format!("no value named {name:?}"))),
        };
        Ok(ok(vec![("value", value)]))
    }

    fn evaluate(&mut self, rest: &str) -> Result<Json, Json> {
        let usage = "evaluate takes a table: {formula = \"...\", entity = \"...\", type = \"real\", unit = \"1\"}";
        let RawValue::Table(table) = toml_value(rest).map_err(|e| error("request", &e))? else {
            return Err(error("request", usage));
        };
        let text = |key: &str| table.get(key).map(|v| v.as_str().ok_or_else(|| error("request", usage))).transpose();
        let formula = text("formula")?.ok_or_else(|| error("request", usage))?;
        let entity = text("entity")?;
        let kind = ty(text("type")?.unwrap_or("real")).map_err(|e| error("request", &e))?;
        let unit = text("unit")?.unwrap_or("1");
        if let Some(key) = table.keys().find(|k| !["formula", "entity", "type", "unit"].contains(&k.as_str())) {
            return Err(error("request", &format!("evaluate: unexpected {key}")));
        }
        let sim = self.sim()?;
        let value = sim.evaluate(formula, entity, kind, unit).map_err(|e| engine_error(&e))?;
        Ok(ok(vec![("value", computed(value))]))
    }

    fn votes(&mut self) -> Result<Json, Json> {
        let sim = self.sim()?;
        let votes = sim.votes().iter().map(|v| {
            Json::obj(vec![
                ("step", Json::Int(v.step as i128)),
                ("lever", Json::str(&v.lever)),
                ("value", v.value.into()),
                ("for", Json::Int(v.votes_for as i128)),
                ("seats", Json::Int(v.seats as i128)),
                ("passed", Json::Bool(v.passed)),
                ("cost", v.cost.map_or(Json::Null, Json::Real)),
                ("refused", Json::Bool(v.refused)),
            ])
        });
        Ok(ok(vec![("votes", Json::Arr(votes.collect()))]))
    }

    fn describe(&self) -> Json {
        let m = &self.model;
        let names = |list: Vec<&String>| Json::Arr(list.into_iter().map(|s| Json::str(s)).collect());
        let dims = m.dims.iter().map(|d| {
            Json::obj(vec![
                ("name", Json::str(&d.name)),
                ("first", d.first.map_or(Json::Null, |f| Json::Int(f as i128))),
                ("members", names(d.members.iter().collect())),
                ("labels", names(d.labels.iter().collect())),
            ])
        });
        let entities = m.entities.iter().map(|e| {
            Json::obj(vec![
                ("name", Json::str(&e.name)),
                ("ids", Json::Arr(e.ids.iter().map(|i| Json::Int(*i as i128)).collect())),
                ("weights", Json::Arr(e.weights.iter().map(|w| Json::Int(*w as i128)).collect())),
                ("weight_state", e.weight_state.as_deref().map_or(Json::Null, Json::str)),
            ])
        });
        let accounts = m.accounts.iter().map(|a| {
            Json::obj(vec![
                ("name", Json::str(&m.symbols[a.sym].name)),
                ("sector", Json::str(&m.sectors[a.sector].name)),
                ("instrument", Json::str(&m.instruments[a.instrument].name)),
            ])
        });
        let dilemmas = m.dilemmas.iter().map(|d| {
            let options = d.options.iter().map(|o| {
                Json::obj(vec![
                    ("name", Json::str(&o.name)),
                    ("label", Json::str(&o.label)),
                    ("doc", Json::str(&o.doc)),
                    ("months", o.months.map_or(Json::Null, |n| Json::Int(n as i128))),
                ])
            });
            Json::obj(vec![
                ("name", Json::str(&d.name)),
                ("label", Json::str(&d.label)),
                ("doc", Json::str(&d.doc)),
                ("again_after", d.again_after.map_or(Json::Null, |n| Json::Int(n as i128))),
                ("options", Json::Arr(options.collect())),
            ])
        });
        let mods = m.mods.iter().map(|x| {
            Json::obj(vec![
                ("id", Json::str(&x.id)),
                ("name", Json::str(&x.name)),
                ("version", Json::str(&x.version)),
                ("description", Json::str(&x.description)),
            ])
        });
        ok(vec![
            ("id", Json::str(&m.id)),
            ("format", Json::Int(m.format as i128)),
            ("currency", Json::str(&m.currency)),
            ("minor", Json::Int(m.minor as i128)),
            ("model_hash", Json::Str(m.model_hash_hex())),
            ("phases", names(m.phases.iter().collect())),
            ("dims", Json::Arr(dims.collect())),
            ("entities", Json::Arr(entities.collect())),
            ("accounts", Json::Arr(accounts.collect())),
            ("dilemmas", Json::Arr(dilemmas.collect())),
            ("mods", Json::Arr(mods.collect())),
            ("mod_notes", names(m.mod_notes.iter().collect())),
        ])
    }

    fn symbols(&self) -> Json {
        let m = &self.model;
        let symbols = m.symbols.iter().map(|d| {
            Json::obj(vec![
                ("name", Json::str(&d.name)),
                ("kind", Json::str(d.kind.name())),
                ("type", Json::str(d.ty.name())),
                ("money", Json::Bool(d.money)),
                ("unit", Json::Str(units::fmt(&Some(d.unit.clone())))),
                ("entity", d.entity.map_or(Json::Null, |e| Json::str(&m.entities[e].name))),
                ("phase", d.phase.map_or(Json::Null, |p| Json::str(&m.phases[p]))),
                ("dims", Json::Arr(d.dims.iter().map(|i| Json::str(&m.dims[*i].name)).collect())),
                ("range", d.range.map_or(Json::Null, |(lo, hi)| Json::Arr(vec![Json::Real(lo), Json::Real(hi)]))),
                ("initial", d.initial.as_ref().map_or(Json::Null, Json::from)),
                ("spec", Json::Obj(d.spec.iter().map(|(k, v)| (k.clone(), v.into())).collect())),
            ])
        });
        ok(vec![("symbols", Json::Arr(symbols.collect()))])
    }

    fn scenario(&self) -> Result<Json, Json> {
        let Some(s) = &self.scenario else { return Err(error("request", "serving a model folder, not a scenario")) };
        let commands = s
            .commands
            .iter()
            .map(|(step, name, value)| Json::Arr(vec![Json::Int(*step as i128), Json::str(name), value.into()]));
        Ok(ok(vec![
            ("name", Json::str(&s.name)),
            ("seed", Json::Int(s.seed as i128)),
            ("steps", Json::Int(s.steps as i128)),
            ("preset", Json::str(&s.preset)),
            ("params", pairs(&s.params)),
            ("levers", pairs(&s.levers)),
            ("commands", Json::Arr(commands.collect())),
        ]))
    }
}

/// `polisim serve <scenario.toml | model folder> [--mod DIR]... [--seed N] [--preset P]`.
pub fn serve(args: &[String]) -> Result<ExitCode, String> {
    let mut path = None;
    let mut mods = Vec::new();
    let (mut seed, mut preset) = (None, None);
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        let mut value = |name: &str| iter.next().cloned().ok_or_else(|| format!("{name} needs a value"));
        match arg.as_str() {
            "--mod" => mods.push(PathBuf::from(value("--mod")?)),
            "--seed" => {
                let n: i128 = value("--seed")?.parse().map_err(|_| "--seed needs a whole number")?;
                seed = Some(n as u64);
            }
            "--preset" => preset = Some(value("--preset")?),
            other if other.starts_with("--") => return Err(format!("unknown option {other}")),
            other if path.is_none() => path = Some(PathBuf::from(other)),
            other => return Err(format!("unexpected argument {other}")),
        }
    }
    let Some(path) = path else { return Err(crate::USAGE.to_string()) };
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    let mut reply = |json: Json| -> Result<(), String> {
        let mut text = json.text();
        text.push('\n');
        out.write_all(text.as_bytes()).and_then(|()| out.flush()).map_err(|e| format!("cannot write a reply: {e}"))
    };
    let mut server = match Server::open(&path, &mods, seed, preset.as_deref()) {
        Ok(server) => server,
        Err(e) => {
            reply(engine_error(&e))?;
            return Ok(ExitCode::from(1));
        }
    };
    reply(server.hello())?;
    for line in std::io::stdin().lock().lines() {
        let line = line.map_err(|e| format!("cannot read a request: {e}"))?;
        match server.handle(&line) {
            Some(json) => reply(json)?,
            None => break,
        }
    }
    Ok(ExitCode::SUCCESS)
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::Server;

    fn toy() -> Server {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../models/toy/scenarios/baseline.toml");
        Server::open(&root, &[], None, None).unwrap()
    }

    fn ask(server: &mut Server, line: &str) -> String {
        server.handle(line).unwrap().text()
    }

    #[test]
    fn steps_reads_and_evaluates() {
        let mut s = toy();
        assert!(s.hello().text().starts_with(r#"{"ok":true,"model":"toy","model_hash":""#));
        let one = ask(&mut s, "step");
        assert!(one.starts_with(r#"{"ok":true,"rows":[{"step":0,"hash":""#), "{one}");
        assert!(ask(&mut s, "step 2").contains(r#""step":2,"#));
        let value = ask(&mut s, "get basic_rate");
        assert!(value.starts_with(r#"{"ok":true,"value":0."#), "{value}");
        assert!(ask(&mut s, "get hh_money").starts_with(r#"{"ok":true,"value":["#));
        assert_eq!(ask(&mut s, r#"evaluate {formula = "1 + 2", type = "int"}"#), r#"{"ok":true,"value":3}"#);
        assert_eq!(ask(&mut s, r#"evaluate {formula = "1.0 / 0.0"}"#), r#"{"ok":true,"value":Infinity}"#);
        assert!(ask(&mut s, "model").contains(r#""dims":"#));
        assert!(ask(&mut s, "symbols").contains(r#""name":"basic_rate","kind":"lever""#));
        assert!(ask(&mut s, "scenario").contains(r#""name":"baseline""#));
        assert_eq!(ask(&mut s, "votes"), r#"{"ok":true,"votes":[]}"#);
        assert!(s.handle("quit").is_none());
    }

    #[test]
    fn a_new_run_and_a_lever_set_for_the_next_step() {
        let mut s = toy();
        assert_eq!(
            ask(&mut s, r#"new {seed = 20261113, preset = "central", levers = {basic_rate = 0.3}}"#),
            r#"{"ok":true}"#
        );
        assert!(ask(&mut s, "step").contains(r#""basic_rate":0.3,"#));
        assert_eq!(ask(&mut s, "set basic_rate 0.25"), r#"{"ok":true}"#);
        assert!(ask(&mut s, "step").contains(r#""basic_rate":0.25,"#));
        // The same seed and settings give the same hashes as a fresh run.
        ask(&mut s, "new {seed = 7}");
        let first = ask(&mut s, "step 3");
        ask(&mut s, "new {seed = 7}");
        assert_eq!(ask(&mut s, "step 3"), first);
    }

    #[test]
    fn several_runs_side_by_side() {
        let mut s = toy();
        assert_eq!(ask(&mut s, "open {seed = 7}"), r#"{"ok":true,"run":1}"#);
        assert_eq!(ask(&mut s, r#"open {seed = 7, levers = {basic_rate = 0.3}}"#), r#"{"ok":true,"run":2}"#);
        ask(&mut s, "@1 step 2");
        assert!(ask(&mut s, "@2 step").contains(r#""step":0,"#));
        assert!(ask(&mut s, "@1 step").contains(r#""step":2,"#));
        assert!(ask(&mut s, "@2 get basic_rate").ends_with(":0.3}"));
        assert_eq!(ask(&mut s, "@1 close"), r#"{"ok":true}"#);
        assert!(ask(&mut s, "@1 step").contains(r#""error":"no run 1""#));
        // A closed run's number is used again; one that cannot start is not kept.
        assert_eq!(ask(&mut s, "open"), r#"{"ok":true,"run":1}"#);
        assert!(ask(&mut s, "open {levers = {nothing = 1}}").contains(r#""kind":"model""#));
        assert_eq!(ask(&mut s, "open"), r#"{"ok":true,"run":3}"#);
        assert!(ask(&mut s, "@x step").contains(r#""kind":"request""#));
    }

    #[test]
    fn errors_come_back_with_their_kind() {
        let mut s = toy();
        assert!(ask(&mut s, "fly").contains(r#""kind":"request""#));
        assert!(ask(&mut s, "new {params = {no_such = 1}}").contains(r#""kind":"model""#));
        // Until a run starts, every request about it repeats why it could not.
        assert!(ask(&mut s, "step").contains(r#""kind":"model""#));
        ask(&mut s, "new");
        assert!(ask(&mut s, r#"evaluate {formula = "1 +"}"#).contains(r#""kind":"formula""#));
        assert!(ask(&mut s, r#"evaluate {formula = "round(1.0 / 0.0)", type = "int"}"#).contains(r#""kind":"run""#));
        ask(&mut s, "set basic_rate 7.5");
        let failed = ask(&mut s, "step 2");
        assert!(failed.contains(r#""kind":"run""#) && failed.ends_with(r#""rows":[]}"#), "{failed}");
        assert!(ask(&mut s, "get nothing").contains(r#""kind":"request""#));
    }
}
