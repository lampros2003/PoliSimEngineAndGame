//! The step loop (engine contract, section 3). A port of oracle/polisim_oracle/sim.py.
//!
//! One step:
//!   1. apply the commands scheduled for this step (lever changes);
//!   2. for each phase in order: evaluate its vars and flows in dependency order, then
//!      evaluate and commit the `next` value of every state updated in that phase;
//!   3. post every flow to the accounts (double entry);
//!   4. verify the accounting identities and declared ranges;
//!   5. keep the values `prev()` will read, and advance the step counter.
//!
//! After any error the simulation is in an undefined state and must be discarded.

use rayon::prelude::*;
use std::borrow::Cow;
use std::collections::{BTreeMap, HashMap, VecDeque};
use std::sync::Arc;
use std::time::{Duration, Instant};

use sha2::{Digest, Sha256};
use toml::Value;

use crate::compile::compile_formula;
use crate::error::{Error, Result, model_err, sim_err};
use crate::model::{Decl, Kind, Model, Raw, convert};
use crate::program::{Col, Program, Ty, Val};
use crate::units::Unit;
use crate::vm::{self, EvalCtx};

/// How to start a run.
#[derive(Clone, Debug, Default)]
pub struct RunConfig {
    pub seed: u64,
    /// Which of a parameter's `low` / `central` / `high` values to use.
    pub preset: String,
    pub params: Vec<(String, Value)>,
    pub levers: Vec<(String, Value)>,
    /// (step, lever, value). For one lever in one step the last entry wins.
    pub commands: Vec<(u64, String, Value)>,
}

/// A computed value: one for the nation, or one per record.
#[derive(Clone, Debug, PartialEq)]
pub enum Computed {
    One(Val),
    Each(Col),
}

/// Results of one completed step: every national value plus sector totals.
#[derive(Clone, Debug, PartialEq)]
pub struct Row {
    pub step: u64,
    pub hash: [u8; 32],
    /// Parallel to [`Simulation::row_names`].
    pub values: Vec<Val>,
}

#[derive(Clone, Copy)]
enum RowSource {
    Scalar(usize),
    AccountTotal(usize),
    FlowTotal(usize), // index into model.flows
    /// Format 1 (S5.4): bills defeated in the step.
    Defeated,
}

/// Format 1 (S5.4): a vote on a change to a lever with a leaning.
#[derive(Clone, Debug, PartialEq)]
pub struct Vote {
    /// Index of the step whose first part held the vote.
    pub step: u64,
    pub lever: String,
    /// The value the change would have stored.
    pub value: Val,
    /// Seats of the blocs that voted for it, and of all blocs.
    pub votes_for: i64,
    pub seats: i64,
    pub passed: bool,
}

struct Phase {
    order: Vec<usize>,
    states: Vec<usize>,
    /// Stage S10: `order` cut into levels: each symbol reads, within the phase, only
    /// symbols of earlier levels, so a level's symbols can be computed at the same time.
    /// Each level keeps plan order.
    levels: Vec<Vec<usize>>,
}

pub struct Simulation {
    model: Arc<Model>,
    seed: u64,
    /// Steps completed so far, which is also the index of the step to compute next.
    step: u64,
    scal: Vec<Val>,
    cols: Vec<Col>,
    prev_scal: Vec<Val>,
    prev_cols: Vec<Col>,
    progs: Vec<Option<Program>>,
    plan: Vec<Phase>,
    /// Per symbol: read through `prev()` by some formula of the model.
    lagged: Vec<bool>,
    /// Symbols in the state hash, in ascending order of name.
    hashed: Vec<usize>,
    commands: BTreeMap<u64, Vec<(String, Value)>>,
    flow_totals: Vec<i64>,
    row_names: Vec<String>,
    row_sources: Vec<RowSource>,
    /// Per symbol with a formula: what it reads this step, and what it reads through prev().
    pub(crate) deps: Vec<Vec<usize>>,
    pub(crate) lagged_deps: Vec<Vec<usize>>,
    /// Keep end-of-step copies of the whole state so results can be explained.
    tracing: bool,
    /// End-of-step states, newest first: at most three (the last step and the two before).
    pub(crate) snapshots: VecDeque<Snapshot>,
    /// Time spent in each phase, then in posting, since the run started.
    phase_time: Vec<Duration>,
    /// Stage S10: time spent computing each symbol since profiling was switched on, and
    /// how many times; empty while it is off.
    sym_time: Vec<(Duration, u64)>,
    /// Stage S10: symbols worth a thread of their own (records, cells, aggregates, rakes).
    heavy: Vec<bool>,
    /// Each entity's current weights: its data's, or its weight state's (format 1, S4.4).
    weights: Vec<Vec<i64>>,
    /// Format 1 (S5.4): every vote on a lever change, and the defeats in the step running.
    votes: Vec<Vote>,
    defeated: i64,
    /// Per symbol: the compiled rake of a weight state that has one.
    rakes: Vec<Option<RakeProg>>,
}

/// A margin's pairs grouped by cell: cell `c` holds `records[offsets[c]..offsets[c + 1]]`
/// with their counts, records ascending and slots in order within a record.
#[derive(Clone)]
struct Pairs {
    offsets: Vec<usize>,
    records: Vec<u32>,
    counts: Vec<f64>,
}

/// Format 1 (S4.4): a compiled rake (docs/spec/06-model-format-1.md).
struct RakeProg {
    when: Program,
    passes: u32,
    margins: Vec<MarginProg>,
}

struct MarginProg {
    target: usize,
    /// Every slot formula reads only data columns and parameters (no `prev`, random draw
    /// or aggregate), so its pairs are the same in every step: they are built once.
    constant: bool,
    cache: std::sync::OnceLock<Pairs>,
    /// (first member, size, stride) per dimension of the target.
    dims: Vec<(i64, usize, usize)>,
    cells: usize,
    /// Per slot: the count, then one formula per dimension.
    slots: Vec<(Program, Vec<Program>)>,
}

/// The whole state at the end of a step, kept only while tracing.
#[derive(Clone)]
pub(crate) struct Snapshot {
    /// Steps completed when it was taken: 0 is the state before the first step.
    pub(crate) steps_done: u64,
    pub(crate) scal: Vec<Val>,
    pub(crate) cols: Vec<Col>,
}

fn as_int(value: &Val) -> i64 {
    match value {
        Val::I(v) => *v,
        _ => unreachable!("whole number expected"),
    }
}

fn int_column(column: &Col) -> &[i64] {
    match column {
        Col::I(v) => v,
        _ => unreachable!("whole-number column expected"),
    }
}

pub(crate) fn type_of(value: &Val) -> Ty {
    match value {
        Val::I(_) => Ty::Int,
        Val::F(_) => Ty::Real,
        Val::B(_) => Ty::Bool,
    }
}

fn fits(value: i128, name: &str) -> Result<i64> {
    i64::try_from(value).map_err(|_| Error::Sim(format!("{name}: value does not fit in 64 bits")))
}

fn schedule(commands: Vec<(u64, String, Value)>) -> BTreeMap<u64, Vec<(String, Value)>> {
    let mut map: BTreeMap<u64, Vec<(String, Value)>> = BTreeMap::new();
    for (step, lever, value) in commands {
        let entry = map.entry(step).or_default();
        match entry.iter_mut().find(|(name, _)| *name == lever) {
            Some(existing) => existing.1 = value,
            None => entry.push((lever, value)),
        }
    }
    map
}

/// Where parameter values come from: a scenario's preset and overrides, or a save file.
/// Stage S7.0: what a name held in an earlier run, for [`Simulation::carry`].
pub(crate) struct Before {
    /// [`family`] of the element's kind.
    pub family: u8,
    /// The entity's name and the hash of its record ids ([`ids_hash`]), for a per-record value.
    pub entity: Option<(String, [u8; 32])>,
    /// Each dimension's name and members, in order, for a dimensioned value.
    pub dims: Vec<(String, Vec<String>)>,
    pub value: Computed,
}

/// Stage S7.0: what carrying a run onto a changed model left behind.
#[derive(Clone, Debug, Default)]
pub(crate) struct Carry {
    /// Values that started again from their initial value.
    pub reset: Vec<String>,
    /// Levers whose value was outside their new range and was moved to its nearer end.
    pub clamped: Vec<String>,
}

/// The kinds of element whose values can stand in for each other across model versions.
pub(crate) fn family(kind: Kind) -> u8 {
    match kind {
        Kind::Var | Kind::Flow => 0,
        Kind::Lever => 1,
        Kind::Account => 2,
        Kind::State => 3,
        Kind::Param | Kind::Column => 4,
    }
}

/// SHA-256 of an entity's record ids, as little-endian u64s.
pub(crate) fn ids_hash(ids: &[u64]) -> [u8; 32] {
    let mut digest = Sha256::new();
    for id in ids {
        digest.update(id.to_le_bytes());
    }
    digest.finalize().into()
}

enum Fit {
    Inside(Computed),
    Clamped(Computed),
    Outside,
}

/// A carried value against its declared range: a lever's single value is clamped; any
/// other value outside the range cannot be carried.
fn fit_range(d: &Decl, value: Computed) -> Fit {
    let Some((lo, hi)) = d.range else { return Fit::Inside(value) };
    let inside = |v: f64| lo <= v && v <= hi;
    match value {
        Computed::One(v) => {
            let x = match v {
                Val::I(i) => i as f64,
                Val::F(f) => f,
                Val::B(b) => f64::from(u8::from(b)),
            };
            if inside(x) {
                return Fit::Inside(Computed::One(v));
            }
            if d.kind != Kind::Lever {
                return Fit::Outside;
            }
            match v {
                Val::I(_) => Fit::Clamped(Computed::One(Val::I(if x < lo { lo.ceil() } else { hi.floor() } as i64))),
                Val::F(_) if x.is_finite() => Fit::Clamped(Computed::One(Val::F(x.clamp(lo, hi)))),
                _ => Fit::Outside,
            }
        }
        Computed::Each(column) => {
            let ok = match &column {
                Col::I(c) => c.iter().all(|&v| inside(v as f64)),
                Col::F(c) => c.iter().all(|&v| inside(v)),
                Col::B(c) => c.iter().all(|&v| inside(f64::from(u8::from(v)))),
            };
            if ok { Fit::Inside(Computed::Each(column)) } else { Fit::Outside }
        }
    }
}

pub(crate) enum Params {
    Scenario { preset: String, overrides: Vec<(String, Value)> },
    Resolved(Vec<(String, Computed)>),
}

impl Simulation {
    pub fn new(model: Arc<Model>, config: RunConfig) -> Result<Simulation> {
        let params = Params::Scenario { preset: config.preset, overrides: config.params };
        Simulation::build(model, config.seed, params, config.levers, config.commands)
    }

    pub(crate) fn build(
        model: Arc<Model>,
        seed: u64,
        params: Params,
        levers: Vec<(String, Value)>,
        commands: Vec<(u64, String, Value)>,
    ) -> Result<Simulation> {
        let count = model.symbols.len();
        let mut simulation = Simulation {
            model: Arc::clone(&model),
            seed,
            step: 0,
            scal: vec![Val::I(0); count],
            cols: vec![Col::I(Vec::new()); count],
            prev_scal: vec![Val::I(0); count],
            prev_cols: vec![Col::I(Vec::new()); count],
            progs: vec![None; count],
            plan: Vec::new(),
            lagged: vec![false; count],
            hashed: Vec::new(),
            commands: schedule(commands),
            flow_totals: vec![0; model.flows.len()],
            row_names: Vec::new(),
            row_sources: Vec::new(),
            deps: vec![Vec::new(); count],
            lagged_deps: vec![Vec::new(); count],
            tracing: false,
            sym_time: Vec::new(),
            heavy: Vec::new(),
            snapshots: VecDeque::new(),
            phase_time: vec![Duration::ZERO; model.phases.len() + 1],
            weights: model.entities.iter().map(|e| e.weights.clone()).collect(),
            votes: Vec::new(),
            defeated: 0,
            rakes: (0..count).map(|_| None).collect(),
        };
        let m = &*model;
        let minor = m.minor;

        // ---- parameters, levers, data columns
        let (preset, mut overrides, mut resolved) = match params {
            Params::Scenario { preset, overrides } => (preset, overrides, None),
            Params::Resolved(values) => (String::new(), Vec::new(), Some(values)),
        };
        for (id, d) in m.symbols.iter().enumerate() {
            match d.kind {
                Kind::Param => {
                    let what = format!("param {}", d.name);
                    if let Some(values) = &mut resolved {
                        let cells = m.cell_count(&d.dims);
                        let value = match values
                            .iter()
                            .position(|(name, _)| *name == d.name)
                            .map(|i| values.remove(i).1)
                        {
                            Some(Computed::One(value)) if d.dims.is_empty() && type_of(&value) == d.ty => {
                                Computed::One(value)
                            }
                            Some(Computed::Each(column))
                                if !d.dims.is_empty()
                                    && column.len() == cells
                                    && matches!(
                                        (&column, d.ty),
                                        (Col::I(_), Ty::Int) | (Col::F(_), Ty::Real) | (Col::B(_), Ty::Bool)
                                    ) =>
                            {
                                Computed::Each(column)
                            }
                            _ => return model_err(format!("{what}: missing from the save file or of the wrong type")),
                        };
                        simulation.store(id, value)?;
                        continue;
                    }
                    let given = overrides.iter().position(|(name, _)| *name == d.name).map(|i| overrides.remove(i).1);
                    if given.is_none() && !d.dims.is_empty() && d.spec.get("data").is_some() {
                        // Format 1: a column of the data file, one per preset if so declared.
                        let column = match d.spec.get("columns") {
                            Some(Value::Table(columns)) => match columns.get(&preset).and_then(Value::as_str) {
                                Some(c) => c.to_string(),
                                None => return model_err(format!("{what}: no column for the {preset:?} preset")),
                            },
                            _ => d.spec.get("column").and_then(Value::as_str).unwrap_or("value").to_string(),
                        };
                        let texts = d.data_column(&column).expect("read by the loader");
                        let column = text_column(texts, d, minor, &what)?;
                        simulation.store(id, Computed::Each(column))?;
                        continue;
                    }
                    let raw = match given.as_ref().or_else(|| d.spec.get("value")).or_else(|| d.spec.get(&preset)) {
                        Some(raw) => raw,
                        None => return model_err(format!("{what}: no 'value' and no {preset:?} preset")),
                    };
                    let value = convert(Raw::Toml(raw), d.ty, d.money, minor, &what)?;
                    if d.dims.is_empty() {
                        simulation.store(id, Computed::One(value))?;
                    } else {
                        simulation.store(id, Computed::Each(Col::filled(value, m.cell_count(&d.dims))))?;
                    }
                }
                Kind::Column => {
                    let entity = &m.entities[d.entity.expect("columns belong to an entity")];
                    let cells = entity.column(&d.name).expect("checked by the loader");
                    let column = text_column(cells, d, minor, &format!("column {}", d.name))?;
                    simulation.store(id, Computed::Each(column))?;
                }
                _ => {}
            }
        }
        if !overrides.is_empty() {
            let names: Vec<&str> = overrides.iter().map(|(n, _)| n.as_str()).collect();
            return model_err(format!("unknown parameter(s): {}", names.join(", ")));
        }
        if resolved.is_some_and(|left| !left.is_empty()) {
            return model_err("the save file has parameters this model does not declare");
        }
        let mut lever_overrides = levers;
        for d in m.symbols.iter().filter(|d| d.kind == Kind::Lever) {
            let given =
                lever_overrides.iter().position(|(name, _)| *name == d.name).map(|i| lever_overrides.remove(i).1);
            if given.is_some() && d.spec.contains_key("dilemma") {
                return model_err(format!("dilemma {}: it is answered by a command, not set at the start", d.name));
            }
            let raw = given.or_else(|| d.initial.clone()).expect("levers have a default");
            simulation.set_lever(&d.name, &raw)?;
        }
        if !lever_overrides.is_empty() {
            let names: Vec<&str> = lever_overrides.iter().map(|(n, _)| n.as_str()).collect();
            return model_err(format!("unknown lever(s): {}", names.join(", ")));
        }

        // ---- initial state: states and holders' accounts, then issuers' accounts
        for (id, d) in m.symbols.iter().enumerate() {
            if d.kind == Kind::State || (d.kind == Kind::Account && d.initial.is_some()) {
                let value = simulation.initial(d)?;
                simulation.store(id, value)?;
            }
        }
        for (index, instrument) in m.instruments.iter().enumerate() {
            let mut held: i128 = 0;
            for account in m.accounts.iter().filter(|a| a.instrument == index && a.sector != instrument.issuer) {
                held = held.checked_add(simulation.total(account.sym)?).ok_or_else(too_large)?;
            }
            let issuer = &m.symbols[instrument.issuer_account];
            let balance = fits(-held, &format!("account {}", issuer.name))?;
            simulation.store(instrument.issuer_account, Computed::One(Val::I(balance)))?;
        }
        simulation.sync_weights()?;

        // ---- compile formulas and build the evaluation plan
        let mut deps: Vec<Vec<usize>> = vec![Vec::new(); count];
        for (id, d) in m.symbols.iter().enumerate() {
            let Some(expr) = &d.expr else { continue };
            let label = format!("{} {}{}", d.kind.name(), d.name, if d.kind == Kind::State { " (next)" } else { "" });
            let compiled = compile_formula(m, expr, d.entity, &d.dims, d.ty, &d.unit, &label)?;
            for &lagged in &compiled.lagged {
                simulation.lagged[lagged] = true;
            }
            deps[id] = compiled.deps;
            simulation.lagged_deps[id] = compiled.lagged;
            simulation.progs[id] = Some(compiled.prog);
        }
        for (id, d) in m.symbols.iter().enumerate() {
            if d.rake.is_some() {
                let (rake, used, lagged) = compile_rake(m, d)?;
                for &l in &lagged {
                    simulation.lagged[l] = true;
                }
                deps[id] = used;
                simulation.lagged_deps[id] = lagged;
                simulation.rakes[id] = Some(rake);
            }
        }
        simulation.plan = plan(m, &deps)?;
        simulation.deps = deps;
        simulation.heavy = (0..count)
            .map(|id| {
                let d = &m.symbols[id];
                let prog = simulation.progs[id].as_ref();
                d.entity.is_some()
                    || !d.dims.is_empty()
                    || simulation.rakes[id].is_some()
                    || prog.is_some_and(|p| !p.aggs.is_empty() || !p.aggs_by.is_empty() || !p.subs.is_empty())
            })
            .collect();

        // ---- values that prev() sees during the first step
        let mut lagged: Vec<usize> = (0..count).filter(|id| simulation.lagged[*id]).collect();
        lagged.sort_by(|a, b| m.symbols[*a].name.cmp(&m.symbols[*b].name));
        for id in lagged {
            let d = &m.symbols[id];
            if matches!(d.kind, Kind::Var | Kind::Flow) {
                if d.initial.is_none() {
                    return model_err(format!(
                        "{} {} is read through prev() and needs 'initial'",
                        d.kind.name(),
                        d.name
                    ));
                }
                let value = simulation.initial(d)?;
                simulation.store(id, value)?;
            }
        }
        simulation.remember();

        simulation.hashed = (0..count)
            .filter(|id| {
                matches!(m.symbols[*id].kind, Kind::Lever | Kind::Account | Kind::State) || simulation.lagged[*id]
            })
            .collect();
        simulation.hashed.sort_by(|a, b| m.symbols[*a].name.cmp(&m.symbols[*b].name));

        for (id, d) in m.symbols.iter().enumerate() {
            if d.kind == Kind::Param || !d.dims.is_empty() {
                continue;
            }
            if d.entity.is_none() {
                simulation.row_names.push(d.name.clone());
                simulation.row_sources.push(RowSource::Scalar(id));
            } else if d.kind == Kind::Account {
                simulation.row_names.push(format!("{}.total", d.name));
                simulation.row_sources.push(RowSource::AccountTotal(id));
            } else if d.kind == Kind::Flow {
                let flow = m.flows.iter().position(|f| f.sym == id).expect("every flow symbol is a flow");
                simulation.row_names.push(format!("{}.total", d.name));
                simulation.row_sources.push(RowSource::FlowTotal(flow));
            }
        }
        if m.legislature.is_some() {
            simulation.row_names.push("bills_defeated".to_string());
            simulation.row_sources.push(RowSource::Defeated);
        }
        Ok(simulation)
    }

    // ------------------------------------------------------------------ helpers

    pub fn model(&self) -> &Model {
        &self.model
    }

    pub fn seed(&self) -> u64 {
        self.seed
    }

    /// Steps completed so far.
    pub fn steps_done(&self) -> u64 {
        self.step
    }

    /// Replaces the commands still to be applied.
    pub fn set_commands(&mut self, commands: Vec<(u64, String, Value)>) {
        self.commands = schedule(commands);
    }

    fn initial(&self, d: &Decl) -> Result<Computed> {
        let minor = self.model.minor;
        let what = format!("{} {} initial", d.kind.name(), d.name);
        let Some(raw) = &d.initial else { return model_err(format!("{what}: missing")) };
        if !d.dims.is_empty() {
            if let Value::Table(table) = raw {
                let column = table.get("column").and_then(Value::as_str).unwrap_or("value");
                let texts = d.data_column(column).expect("read by the loader");
                return Ok(Computed::Each(text_column(texts, d, minor, &what)?));
            }
            let value = convert(Raw::Toml(raw), d.ty, d.money, minor, &what)?;
            return Ok(Computed::Each(Col::filled(value, self.model.cell_count(&d.dims))));
        }
        let Some(entity) = d.entity else {
            return Ok(Computed::One(convert(Raw::Toml(raw), d.ty, d.money, minor, &what)?));
        };
        let entity = &self.model.entities[entity];
        if let Value::Table(table) = raw {
            let cells = match table.get("column").and_then(Value::as_str).and_then(|name| entity.column(name)) {
                Some(cells) => cells,
                None => return model_err(format!("{what}: needs {{ column = \"...\" }} naming a column of the data")),
            };
            return Ok(Computed::Each(text_column(cells, d, minor, &what)?));
        }
        Ok(Computed::Each(Col::filled(convert(Raw::Toml(raw), d.ty, d.money, minor, &what)?, entity.len())))
    }

    /// Type-level and declared-range checks, then the value becomes current.
    fn store(&mut self, id: usize, value: Computed) -> Result<()> {
        let d = &self.model.symbols[id];
        let fail = |shown: String| -> Result<()> {
            sim_err(format!("{} {}: {shown} is outside its declared range", d.kind.name(), d.name))
        };
        let not_finite = || -> Result<()> { sim_err(format!("{} {}: value is not finite", d.kind.name(), d.name)) };
        let (lo, hi) = d.range.unwrap_or((f64::NEG_INFINITY, f64::INFINITY));
        let ranged = d.range.is_some();
        let minor = self.model.minor as f64;
        let check_int = |v: i64| -> Result<()> {
            if ranged && !(lo <= v as f64 && v as f64 <= hi) {
                return fail(if d.money { format!("{}", v as f64 / minor) } else { v.to_string() });
            }
            Ok(())
        };
        let check_real = |v: f64| -> Result<()> {
            if !v.is_finite() {
                return not_finite();
            }
            if ranged && !(lo <= v && v <= hi) {
                return fail(v.to_string());
            }
            Ok(())
        };
        let check_bool = |v: bool| -> Result<()> {
            let as_real = if v { 1.0 } else { 0.0 };
            if ranged && !(lo <= as_real && as_real <= hi) {
                return fail(v.to_string());
            }
            Ok(())
        };
        match &value {
            Computed::One(Val::I(v)) => check_int(*v)?,
            Computed::One(Val::F(v)) => check_real(*v)?,
            Computed::One(Val::B(v)) => check_bool(*v)?,
            Computed::Each(Col::I(column)) => column.iter().try_for_each(|v| check_int(*v))?,
            Computed::Each(Col::F(column)) => column.iter().try_for_each(|v| check_real(*v))?,
            Computed::Each(Col::B(column)) => {
                if ranged {
                    column.iter().try_for_each(|v| check_bool(*v))?
                }
            }
        }
        match value {
            Computed::One(v) => self.scal[id] = v,
            Computed::Each(column) => self.cols[id] = column,
        }
        Ok(())
    }

    /// Sector-level total of a national or per-record whole-number quantity.
    fn total(&self, id: usize) -> Result<i128> {
        let d = &self.model.symbols[id];
        let Some(entity) = d.entity else { return Ok(as_int(&self.scal[id]) as i128) };
        let mut total: i128 = 0;
        for (w, v) in self.weights[entity].iter().zip(int_column(&self.cols[id])) {
            total = total.checked_add(*w as i128 * *v as i128).ok_or_else(too_large)?;
        }
        Ok(total)
    }

    /// Checks that `raw` is a legal setting for the lever `name` without applying it.
    /// Returns the value as it would be stored.
    pub fn check_lever(&self, name: &str, raw: &Value) -> Result<Val> {
        self.check_answer(name, raw)?;
        check_lever(&self.model, name, raw)
    }

    /// Stage S9.1: an answer to a dilemma is a whole number from 1 to the number of its
    /// answers, given while it is open (at the start of the step). Other levers pass.
    fn check_answer(&self, name: &str, raw: &Value) -> Result<()> {
        let Some(&id) = self.model.sym_index.get(name) else { return Ok(()) };
        let d = &self.model.symbols[id];
        if d.kind != Kind::Lever || !d.spec.contains_key("dilemma") {
            return Ok(());
        }
        let open = self.model.sym_index[&format!("{name}_open")];
        if !matches!(self.scal[open], Val::B(true)) {
            return sim_err(format!("dilemma {name} is not open"));
        }
        let value = convert(Raw::Toml(raw), d.ty, d.money, self.model.minor, &format!("dilemma {name}"))?;
        let count = d.range.map_or(0.0, |(_, hi)| hi);
        if !matches!(value, Val::I(v) if v >= 1 && v as f64 <= count) {
            return sim_err(format!("dilemma {name}: the answer must be from 1 to {count}"));
        }
        Ok(())
    }

    fn set_lever(&mut self, name: &str, raw: &Value) -> Result<()> {
        let id = match self.model.sym_index.get(name) {
            Some(id) if self.model.symbols[*id].kind == Kind::Lever => *id,
            _ => return model_err(format!("{name:?} is not a lever")),
        };
        let d = &self.model.symbols[id];
        let value = convert(Raw::Toml(raw), d.ty, d.money, self.model.minor, &format!("lever {name}"))?;
        self.store(id, Computed::One(value))
    }

    /// Format 1 (S5.4): a change to a lever with a leaning is a bill. The leading bloc (the
    /// governing bloc with the most seats, the first on a tie) votes for it; every other bloc
    /// votes for it if the move is towards it from the leader's position (from 0 with no
    /// leader). It passes with more than half the seats. Every vote is kept (see
    /// [`Simulation::votes`]).
    fn passes(&mut self, name: &str, raw: &Value) -> Result<bool> {
        let model = Arc::clone(&self.model);
        let Some(legislature) = model.legislature else { return Ok(true) };
        let Some(&id) = model.sym_index.get(name) else { return Ok(true) };
        let d = &model.symbols[id];
        let Some(leaning) = d.spec.get("leaning").and_then(Value::as_str).filter(|_| d.kind == Kind::Lever) else {
            return Ok(true);
        };
        let new = convert(Raw::Toml(raw), d.ty, d.money, model.minor, &format!("lever {name}"))?;
        let old = self.scal[id];
        let up = match (new, old) {
            (Val::I(a), Val::I(b)) if a != b => a > b,
            (Val::F(a), Val::F(b)) if a != b => a > b,
            _ => return Ok(true),
        };
        let left = up == (leaning == "left");
        let (Col::I(seats), Col::B(governing), Col::F(position)) =
            (&self.cols[legislature.seats], &self.cols[legislature.governing], &self.cols[legislature.position])
        else {
            unreachable!("checked by the loader")
        };
        let mut leader: Option<usize> = None;
        for (b, (n, g)) in seats.iter().zip(governing).enumerate() {
            if *g && leader.is_none_or(|l| *n > seats[l]) {
                leader = Some(b);
            }
        }
        let here = leader.map_or(0.0, |l| position[l]);
        let mut votes_for: i128 = 0;
        let mut everyone: i128 = 0;
        for (b, (n, p)) in seats.iter().zip(position).enumerate() {
            everyone += *n as i128;
            if Some(b) == leader || (left && *p < here) || (!left && *p > here) {
                votes_for += *n as i128;
            }
        }
        let passed = 2 * votes_for > everyone;
        self.votes.push(Vote {
            step: self.step,
            lever: name.to_string(),
            value: new,
            votes_for: fits(votes_for, "seats")?,
            seats: fits(everyone, "seats")?,
            passed,
        });
        if !passed {
            self.defeated += 1;
        }
        Ok(passed)
    }

    /// Stage S6.1: per symbol, what its formula reads this step and through `prev()`.
    pub fn dependencies(&self) -> (&[Vec<usize>], &[Vec<usize>]) {
        (&self.deps, &self.lagged_deps)
    }

    /// Format 1 (S5.4): every vote on a lever change since the run started (or resumed).
    pub fn votes(&self) -> &[Vote] {
        &self.votes
    }

    fn remember(&mut self) {
        for id in 0..self.lagged.len() {
            if self.lagged[id] {
                if !self.model.symbols[id].columnar() {
                    self.prev_scal[id] = self.scal[id];
                } else {
                    self.prev_cols[id].clone_from(&self.cols[id]);
                }
            }
        }
    }

    fn ctx(&self) -> EvalCtx<'_> {
        EvalCtx {
            scal: &self.scal,
            cols: &self.cols,
            prev_scal: &self.prev_scal,
            prev_cols: &self.prev_cols,
            entities: &self.model.entities,
            weights: &self.weights,
            seed: self.seed,
            step: self.step as u32,
            swap: None,
        }
    }

    /// Format 1 (S4.4): copies weight states into the weights every aggregate reads.
    fn sync_weights(&mut self) -> Result<()> {
        let model = Arc::clone(&self.model);
        for (index, entity) in model.entities.iter().enumerate() {
            let Some(state) = &entity.weight_state else { continue };
            let id = model.sym_index[state];
            let values = int_column(&self.cols[id]);
            if values.iter().any(|w| *w < 1) {
                return sim_err(format!("state {state}: weights must be whole numbers of at least 1"));
            }
            self.weights[index].clone_from_slice(values);
        }
        Ok(())
    }

    /// The weights that go with a copy of the state: each weight state's value in `cols`.
    pub(crate) fn weights_in(&self, cols: &[Col]) -> Vec<Vec<i64>> {
        let model = &self.model;
        model
            .entities
            .iter()
            .map(|e| match &e.weight_state {
                Some(state) => int_column(&cols[model.sym_index[state]]).to_vec(),
                None => e.weights.clone(),
            })
            .collect()
    }

    /// Runs a weight state's rake: the new weights (docs/spec/06-model-format-1.md).
    fn rake(&self, id: usize, rake: &RakeProg) -> Result<Computed> {
        let d = &self.model.symbols[id];
        let what = format!("state {} rake", d.name);
        let named = |message: String| Error::Sim(format!("{what}: {message}"));
        let cx = self.ctx();
        let current = int_column(&self.cols[id]);
        if vm::eval_scalar(&rake.when, &cx).map_err(named)? != Val::B(true) {
            return Ok(Computed::Each(Col::I(current.to_vec())));
        }
        let entity = d.entity.expect("weight states belong to an entity");
        let count = current.len();
        // Per margin: the target as reals, and its pairs grouped by cell, records ascending
        // and slots in order (offsets into `records` and `counts`).
        let mut prepared = Vec::with_capacity(rake.margins.len());
        for margin in &rake.margins {
            let target: Vec<f64> = match &self.cols[margin.target] {
                Col::I(v) => v.iter().map(|x| *x as f64).collect(),
                Col::F(v) => v.clone(),
                Col::B(_) => unreachable!("targets are numbers"),
            };
            if let Some(x) = target.iter().find(|x| !x.is_finite() || **x < 0.0) {
                let name = &self.model.symbols[margin.target].name;
                return sim_err(format!(
                    "{what}: a cell of the target {name} is {}, not a finite number of at least 0",
                    crate::pyfmt::float_repr(*x)
                ));
            }
            let pairs: Cow<Pairs> = if margin.constant {
                match margin.cache.get() {
                    Some(pairs) => Cow::Borrowed(pairs),
                    None => {
                        let pairs = self.rake_pairs(margin, entity, count, &cx, &what)?;
                        Cow::Borrowed(margin.cache.get_or_init(|| pairs))
                    }
                }
            } else {
                Cow::Owned(self.rake_pairs(margin, entity, count, &cx, &what)?)
            };
            prepared.push((target, pairs));
        }
        let mut v: Vec<f64> = current.iter().map(|w| *w as f64).collect();
        for _ in 0..rake.passes {
            for (target, pairs) in &prepared {
                let Pairs { offsets, records, counts } = pairs.as_ref();
                for cell in 0..target.len() {
                    let range = offsets[cell]..offsets[cell + 1];
                    let mut total = 0.0f64;
                    for k in range.clone() {
                        total += v[records[k] as usize] * counts[k];
                    }
                    let goal = target[cell];
                    if total > 0.0 && goal > 0.0 {
                        let f = goal / total;
                        let mut last = u32::MAX;
                        for &r in &records[range] {
                            if r != last {
                                v[r as usize] *= f;
                                last = r;
                            }
                        }
                    }
                }
            }
        }
        let mut out = Vec::with_capacity(count);
        for x in v {
            if !x.is_finite() {
                return sim_err(format!("{what}: a weight is not finite"));
            }
            let w = x.round_ties_even();
            if !(-9_223_372_036_854_775_808.0..9_223_372_036_854_775_808.0).contains(&w) {
                return sim_err(format!("{what}: a weight does not fit in 64 bits"));
            }
            out.push((w as i64).max(1));
        }
        Ok(Computed::Each(Col::I(out)))
    }

    /// A margin's pairs: its slots' `count` and `at` evaluated for every record, checked,
    /// and grouped by cell, records ascending and slots in order within a record.
    fn rake_pairs(&self, margin: &MarginProg, entity: usize, count: usize, cx: &EvalCtx, what: &str) -> Result<Pairs> {
        let named = |message: String| Error::Sim(format!("{what}: {message}"));
        let mut counts = Vec::with_capacity(margin.slots.len());
        let mut ats = Vec::with_capacity(margin.slots.len());
        for (count_prog, at_progs) in &margin.slots {
            let column = vm::eval_column(count_prog, entity, cx).map_err(named)?;
            let Col::F(column) = column else { unreachable!("counts are compiled as reals") };
            counts.push(column);
            let mut columns = Vec::with_capacity(at_progs.len());
            for prog in at_progs {
                let Col::I(column) = vm::eval_column(prog, entity, cx).map_err(named)? else {
                    unreachable!("members are whole numbers")
                };
                columns.push(column);
            }
            ats.push(columns);
        }
        let mut cell_of: Vec<(usize, usize, f64)> = Vec::new(); // (cell, record, count)
        for r in 0..count {
            for (slot, column) in counts.iter().enumerate() {
                let c = column[r];
                if !c.is_finite() || c < 0.0 {
                    return sim_err(format!(
                        "{what}: a record's count is {}, not a finite number of at least 0",
                        crate::pyfmt::float_repr(c)
                    ));
                }
                if c == 0.0 {
                    continue;
                }
                let mut flat = 0usize;
                for (k, &(first, size, stride)) in margin.dims.iter().enumerate() {
                    let v = ats[slot][k][r];
                    let pos = v.checked_sub(first).filter(|p| (0..size as i64).contains(p));
                    let Some(pos) = pos else {
                        let dim = &self.model.dims[self.model.symbols[margin.target].dims[k]].name;
                        return sim_err(format!("{what}: a record's member {v} is not in {dim}"));
                    };
                    flat += pos as usize * stride;
                }
                cell_of.push((flat, r, c));
            }
        }
        // Group by cell, keeping the order within each cell (a stable counting sort).
        let mut offsets = vec![0usize; margin.cells + 1];
        for &(cell, _, _) in &cell_of {
            offsets[cell + 1] += 1;
        }
        for k in 0..margin.cells {
            offsets[k + 1] += offsets[k];
        }
        let mut fill = offsets.clone();
        let mut records = vec![0u32; cell_of.len()];
        let mut weights = vec![0.0f64; cell_of.len()];
        for &(cell, r, c) in &cell_of {
            records[fill[cell]] = r as u32;
            weights[fill[cell]] = c;
            fill[cell] += 1;
        }
        Ok(Pairs { offsets, records, counts: weights })
    }

    fn compute(&self, id: usize) -> Result<Computed> {
        if let Some(rake) = &self.rakes[id] {
            return self.rake(id, rake);
        }
        let d = &self.model.symbols[id];
        let prog = self.progs[id].as_ref().expect("planned symbols have a program");
        let named = |message: String| Error::Sim(format!("{} {}: {message}", d.kind.name(), d.name));
        if !d.dims.is_empty() {
            let cells = self.model.cell_count(&d.dims);
            return vm::eval_cells(prog, cells, &self.ctx()).map(Computed::Each).map_err(named);
        }
        match d.entity {
            None => vm::eval_scalar(prog, &self.ctx()).map(Computed::One).map_err(named),
            Some(entity) => vm::eval_column(prog, entity, &self.ctx()).map(Computed::Each).map_err(named),
        }
    }

    // ------------------------------------------------------------------ the step

    /// Runs one step and returns its results.
    pub fn step(&mut self) -> Result<Row> {
        let index = self.step;
        match self.step_inner() {
            Ok(()) => {}
            Err(Error::Sim(message)) => return sim_err(format!("step {index}: {message}")),
            Err(other) => return Err(other),
        }
        self.remember();
        self.step += 1;
        if self.tracing {
            self.take_snapshot();
        }
        self.record()
    }

    /// After a step fails part-way, puts every value back as it was at the end of the last
    /// completed step, so that a corrected model can be reloaded and the run continued.
    /// It uses the end-of-step copy kept while tracing; without one it returns false and
    /// the state is left as the failed step left it.
    pub fn roll_back(&mut self) -> bool {
        match self.snapshots.front() {
            Some(s) if s.steps_done == self.step => {
                self.scal.clone_from(&s.scal);
                self.cols.clone_from(&s.cols);
                self.sync_weights().is_ok()
            }
            _ => false,
        }
    }

    fn take_snapshot(&mut self) {
        let snapshot = Snapshot { steps_done: self.step, scal: self.scal.clone(), cols: self.cols.clone() };
        self.snapshots.push_front(snapshot);
        self.snapshots.truncate(3);
    }

    /// Keeps copies of the state at the end of each step so that [`Simulation::explain`]
    /// can say why a value changed. It costs one copy of the state per step and changes no
    /// result. Explanations become available two steps after it is turned on.
    pub fn set_tracing(&mut self, on: bool) {
        self.tracing = on;
        self.snapshots.clear();
        if on {
            self.take_snapshot();
        }
    }

    pub fn is_tracing(&self) -> bool {
        self.tracing
    }

    pub(crate) fn progs_of(&self, id: usize) -> Option<&Program> {
        self.progs[id].as_ref()
    }

    /// Stage S10: records the time each symbol's formula takes from now on (off by default;
    /// switching it on again starts the counts afresh).
    pub fn set_profiling(&mut self, on: bool) {
        self.sym_time = if on { vec![(Duration::ZERO, 0); self.model.symbols.len()] } else { Vec::new() };
    }

    /// Stage S10: each symbol's total time and count of evaluations since profiling was
    /// switched on, slowest first; symbols never evaluated are left out.
    pub fn symbol_times(&self) -> Vec<(String, Duration, u64)> {
        let mut out: Vec<(String, Duration, u64)> = self
            .sym_time
            .iter()
            .enumerate()
            .filter(|(_, (_, n))| *n > 0)
            .map(|(id, (t, n))| (self.model.symbols[id].name.clone(), *t, *n))
            .collect();
        out.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
        out
    }

    /// Stage S10: the phase's vars and flows, level by level; false if any failed (to be
    /// run again in plan order).
    fn run_levels(&mut self, phase: usize) -> bool {
        for level in 0..self.plan[phase].levels.len() {
            let ids = self.plan[phase].levels[level].clone();
            let Some(values) = self.compute_all(&ids) else { return false };
            for (id, value) in values {
                if self.store(id, value).is_err() {
                    return false;
                }
            }
        }
        true
    }

    /// Stage S10: computes symbols that do not read one another: at the same time when at
    /// least two are heavy, else one after another. None if any failed.
    fn compute_all(&mut self, ids: &[usize]) -> Option<Vec<(usize, Computed)>> {
        if ids.iter().filter(|id| self.heavy[**id]).count() < 2 {
            let mut out = Vec::with_capacity(ids.len());
            for &id in ids {
                out.push((id, self.compute_timed(id).ok()?));
            }
            return Some(out);
        }
        let this = &*self;
        let results: Vec<(usize, Result<Computed>, Duration)> = ids
            .par_iter()
            .map(|&id| {
                let started = Instant::now();
                let value = this.compute(id);
                (id, value, started.elapsed())
            })
            .collect();
        let mut out = Vec::with_capacity(ids.len());
        for (id, value, spent) in results {
            if let Some(entry) = self.sym_time.get_mut(id) {
                entry.0 += spent;
                entry.1 += 1;
            }
            out.push((id, value.ok()?));
        }
        Some(out)
    }

    /// Computes a symbol, timing it when profiling is on.
    fn compute_timed(&mut self, id: usize) -> Result<Computed> {
        if self.sym_time.is_empty() {
            return self.compute(id);
        }
        let started = Instant::now();
        let value = self.compute(id);
        let entry = &mut self.sym_time[id];
        entry.0 += started.elapsed();
        entry.1 += 1;
        value
    }

    /// Time spent so far in each phase, by name, then in posting.
    pub fn phase_times(&self) -> Vec<(String, Duration)> {
        let names = self.model.phases.iter().cloned().chain(std::iter::once("posting".to_string()));
        names.zip(self.phase_time.iter().copied()).collect()
    }

    fn step_inner(&mut self) -> Result<()> {
        self.defeated = 0;
        if let Some(commands) = self.commands.get(&self.step).cloned() {
            for (lever, raw) in commands {
                self.check_answer(&lever, &raw)?;
                if self.passes(&lever, &raw)? {
                    self.set_lever(&lever, &raw)?;
                }
            }
        }
        for phase in 0..self.plan.len() {
            let started = Instant::now();
            // Stage S10: level by level, several symbols at once. A symbol's value depends
            // only on what it reads, so the values are those of the plan order; if anything
            // fails, the phase runs again in plan order, which stops at the error one thread
            // would have met first.
            if !self.run_levels(phase) {
                for position in 0..self.plan[phase].order.len() {
                    let id = self.plan[phase].order[position];
                    let value = self.compute_timed(id)?;
                    self.store(id, value)?;
                }
            }
            let states = self.plan[phase].states.clone();
            let pending = match self.compute_all(&states) {
                Some(values) => values,
                None => {
                    let mut pending = Vec::with_capacity(states.len());
                    for &id in &states {
                        pending.push((id, self.compute_timed(id)?));
                    }
                    pending
                }
            };
            let mut weights_changed = false;
            for (id, value) in pending {
                weights_changed |= self.rakes[id].is_some() || self.is_weight_state(id);
                self.store(id, value)?;
            }
            if weights_changed {
                self.sync_weights()?;
            }
            self.phase_time[phase] += started.elapsed();
        }
        let started = Instant::now();
        let posted = self.post_flows();
        let last = self.phase_time.len() - 1;
        self.phase_time[last] += started.elapsed();
        posted?;
        // Stage S9.1: an answer to a dilemma lasts one step; between steps its lever is 0.
        let model = Arc::clone(&self.model);
        for dilemma in &model.dilemmas {
            let id = model.sym_index[&dilemma.name];
            self.store(id, Computed::One(Val::I(0)))?;
        }
        Ok(())
    }

    /// Double entry: every flow leaves one account and enters another (contract, section 4).
    fn post_flows(&mut self) -> Result<()> {
        let model = Arc::clone(&self.model);
        let m = &*model;
        let accounts: Vec<usize> = m.accounts.iter().map(|a| a.sym).collect();
        let slot = |sym: usize| accounts.iter().position(|a| *a == sym).expect("flows use declared accounts");
        let mut before = Vec::with_capacity(accounts.len());
        for &sym in &accounts {
            before.push(self.total(sym)?);
        }
        let mut net = vec![0i128; accounts.len()];
        let mut scalars: Vec<Option<i64>> = Vec::with_capacity(accounts.len());
        let mut columns: Vec<Option<Vec<i64>>> = Vec::with_capacity(accounts.len());
        for &sym in &accounts {
            if m.symbols[sym].entity.is_none() {
                scalars.push(Some(as_int(&self.scal[sym])));
                columns.push(None);
            } else {
                scalars.push(None);
                columns.push(Some(int_column(&self.cols[sym]).to_vec()));
            }
        }

        for (index, flow) in m.flows.iter().enumerate() {
            let d = &m.symbols[flow.sym];
            let (total, amounts): (i128, Option<&[i64]>) = match d.entity {
                None => {
                    let amount = as_int(&self.scal[flow.sym]);
                    if amount < 0 {
                        return sim_err(format!("flow {} is negative", d.name));
                    }
                    (amount as i128, None)
                }
                Some(entity) => {
                    let amounts = int_column(&self.cols[flow.sym]);
                    if amounts.iter().any(|a| *a < 0) {
                        return sim_err(format!("flow {} is negative for at least one record", d.name));
                    }
                    let mut total: i128 = 0;
                    for (w, a) in self.weights[entity].iter().zip(amounts) {
                        total = total.checked_add(*w as i128 * *a as i128).ok_or_else(too_large)?;
                    }
                    (total, Some(amounts))
                }
            };
            let total64 = fits(total, &format!("flow {}", d.name))?;
            // Flows are applied in declaration order and every intermediate balance must fit.
            for (account, sign) in [(flow.src_account, -1i64), (flow.dst_account, 1i64)] {
                let k = slot(account);
                let name = &m.symbols[account].name;
                if let Some(balance) = &mut scalars[k] {
                    *balance = fits(*balance as i128 + sign as i128 * total, name)?;
                } else if let (Some(column), Some(amounts)) = (&mut columns[k], amounts) {
                    for (balance, amount) in column.iter_mut().zip(amounts) {
                        *balance = match balance.checked_add(sign * *amount) {
                            Some(v) => v,
                            None => return sim_err(format!("{name}: value does not fit in 64 bits")),
                        };
                    }
                } else {
                    return sim_err(format!("flow {}: internal error, account shape", d.name));
                }
                net[k] += sign as i128 * total;
            }
            self.flow_totals[index] = total64;
        }

        for (k, &sym) in accounts.iter().enumerate() {
            if let Some(balance) = scalars[k] {
                self.store(sym, Computed::One(Val::I(balance)))?;
            }
        }
        for (k, &sym) in accounts.iter().enumerate() {
            if let Some(column) = columns[k].take() {
                self.store(sym, Computed::Each(Col::I(column)))?;
            }
        }

        // Identities. They hold by construction; they are checked because this route to
        // the totals is not the oracle's.
        let mut totals = Vec::with_capacity(accounts.len());
        for (k, &sym) in accounts.iter().enumerate() {
            let name = &m.symbols[sym].name;
            let total = fits(self.total(sym)?, name)? as i128;
            if total != before[k] + net[k] {
                return sim_err(format!("account {name}: balance change differs from its net flows"));
            }
            totals.push(total);
        }
        for (index, instrument) in m.instruments.iter().enumerate() {
            let sum: i128 =
                m.accounts.iter().zip(&totals).filter(|(a, _)| a.instrument == index).map(|(_, t)| *t).sum();
            if sum != 0 {
                return sim_err(format!("instrument {}: balances sum to {sum}, not zero", instrument.name));
            }
        }
        Ok(())
    }

    // ------------------------------------------------------------------ outputs

    /// Column names of [`Row::values`]: every national value, then `<name>.total` for
    /// per-record accounts and flows, in declaration order.
    pub fn row_names(&self) -> &[String] {
        &self.row_names
    }

    fn record(&self) -> Result<Row> {
        let mut values = Vec::with_capacity(self.row_sources.len());
        for source in &self.row_sources {
            values.push(match *source {
                RowSource::Scalar(id) => self.scal[id],
                RowSource::AccountTotal(id) => Val::I(fits(self.total(id)?, &self.model.symbols[id].name)?),
                RowSource::FlowTotal(flow) => Val::I(self.flow_totals[flow]),
                RowSource::Defeated => Val::I(self.defeated),
            });
        }
        Ok(Row { step: self.step - 1, hash: self.state_hash(), values })
    }

    /// Current per-record values of a symbol.
    pub fn column(&self, name: &str) -> Option<&Col> {
        let id = *self.model.sym_index.get(name)?;
        self.model.symbols[id].columnar().then(|| &self.cols[id])
    }

    /// Current national value of a symbol.
    pub fn scalar(&self, name: &str) -> Option<Val> {
        let id = *self.model.sym_index.get(name)?;
        if self.model.symbols[id].columnar() {
            return None;
        }
        Some(self.scal[id])
    }

    /// Evaluates a one-off formula against the current state: one value, or one per record.
    ///
    /// Nothing is stored and no range is checked, so a real result may be an infinity or
    /// not-a-number. Between steps `prev(x)` equals `x`. Random draws use the index of
    /// the step that would run next.
    pub fn evaluate(&self, src: &str, entity: Option<&str>, ty: Ty, unit: &str) -> Result<Computed> {
        let ctx = match entity {
            None => None,
            Some(name) => match self.model.entity_index.get(name) {
                Some(index) => Some(*index),
                None => return model_err(format!("unknown entity {name:?}")),
            },
        };
        let unit = Unit::parse(unit).map_err(Error::Formula)?;
        let compiled = compile_formula(&self.model, src, ctx, &[], ty, &unit, "evaluate")?;
        let cx = EvalCtx { prev_scal: &self.scal, prev_cols: &self.cols, ..self.ctx() };
        match ctx {
            None => vm::eval_scalar(&compiled.prog, &cx).map(Computed::One).map_err(Error::Sim),
            Some(entity) => vm::eval_column(&compiled.prog, entity, &cx).map(Computed::Each).map_err(Error::Sim),
        }
    }

    /// The same run on a changed model: the new model's formulas and parameters, with the
    /// lever settings, balances, states and remembered values carried across by name.
    ///
    /// A value is carried when the new model has a symbol of the same name, kind, type
    /// and shape. The names of persistent values that could not be carried, and so start
    /// from the new model's initial values, are returned with the new simulation.
    /// Commands still to come are carried too. Reloading an unchanged model gives a run
    /// identical to the one that was never reloaded.
    pub fn reload(
        &self,
        model: Arc<Model>,
        preset: &str,
        params: Vec<(String, Value)>,
    ) -> Result<(Simulation, Vec<String>)> {
        let mut commands = Vec::new();
        for (step, list) in &self.commands {
            for (lever, raw) in list {
                if model.sym(lever).is_some_and(|d| d.kind == Kind::Lever) {
                    commands.push((*step, lever.clone(), raw.clone()));
                }
            }
        }
        let source = Params::Scenario { preset: preset.to_string(), overrides: params };
        let mut next = Simulation::build(Arc::clone(&model), self.seed, source, Vec::new(), commands)?;
        let old = &self.model;
        let hashes: Vec<[u8; 32]> = old.entities.iter().map(|e| ids_hash(&e.ids)).collect();
        let carry = next.carry(self.step, |name| {
            let &id = old.sym_index.get(name)?;
            let o = &old.symbols[id];
            // A var or flow that was never computed holds a placeholder; only carry real values.
            if matches!(o.kind, Kind::Var | Kind::Flow) && self.step == 0 && !self.lagged[id] {
                return None;
            }
            Some(Before {
                family: family(o.kind),
                entity: o.entity.map(|e| (old.entities[e].name.clone(), hashes[e])),
                dims: o.dims.iter().map(|&d| (old.dims[d].name.clone(), old.dims[d].members.clone())).collect(),
                value: self.value_now(id),
            })
        })?;
        next.set_tracing(self.tracing);
        let mut reset = carry.reset;
        reset.extend(carry.clamped);
        Ok((next, reset))
    }

    /// Stage S7.0: fills a run just built for a model with the values of an earlier run, by
    /// name: `before(name)` says what that name held. A value is carried when it is the same
    /// kind of element (var or flow, lever, account, state), with the same entity and records
    /// or the same dimensions and members, and the same type; a lever outside its new range is
    /// clamped to it; anything else starts again from its initial value.
    pub(crate) fn carry(&mut self, steps_done: u64, before: impl Fn(&str) -> Option<Before>) -> Result<Carry> {
        let model = Arc::clone(&self.model);
        let hashes: Vec<[u8; 32]> = model.entities.iter().map(|e| ids_hash(&e.ids)).collect();
        let mut values = Vec::new();
        let mut out = Carry::default();
        for &id in &self.hashed {
            let d = &model.symbols[id];
            let dims: Vec<(String, Vec<String>)> =
                d.dims.iter().map(|&i| (model.dims[i].name.clone(), model.dims[i].members.clone())).collect();
            let carried = before(&d.name).and_then(|b| {
                let entity = d.entity.map(|e| (model.entities[e].name.clone(), hashes[e]));
                let ty_ok = match &b.value {
                    Computed::One(v) => !d.columnar() && type_of(v) == d.ty,
                    Computed::Each(c) => {
                        d.columnar()
                            && matches!((c, d.ty), (Col::I(_), Ty::Int) | (Col::F(_), Ty::Real) | (Col::B(_), Ty::Bool))
                    }
                };
                (b.family == family(d.kind) && b.entity == entity && b.dims == dims && ty_ok).then_some(b.value)
            });
            let carried = match carried.map(|value| fit_range(d, value)) {
                Some(Fit::Inside(value)) => Some(value),
                Some(Fit::Clamped(value)) => {
                    out.clamped.push(d.name.clone());
                    Some(value)
                }
                Some(Fit::Outside) | None => None,
            };
            match carried {
                Some(value) => values.push((d.name.clone(), value)),
                None => {
                    out.reset.push(d.name.clone());
                    values.push((d.name.clone(), self.value_now(id)));
                }
            }
        }
        self.restore(steps_done, values)?;
        Ok(out)
    }

    fn value_now(&self, id: usize) -> Computed {
        if self.model.symbols[id].columnar() {
            Computed::Each(self.cols[id].clone())
        } else {
            Computed::One(self.scal[id])
        }
    }

    /// Commands still scheduled, in step order.
    pub fn commands(&self) -> Vec<(u64, String, Value)> {
        let mut out = Vec::new();
        for (step, list) in &self.commands {
            for (lever, raw) in list {
                out.push((*step, lever.clone(), raw.clone()));
            }
        }
        out
    }

    /// Current parameter values, in declaration order.
    pub(crate) fn params(&self) -> Vec<(&str, Computed)> {
        let symbols = self.model.symbols.iter().enumerate();
        symbols.filter(|(_, d)| d.kind == Kind::Param).map(|(id, d)| (d.name.as_str(), self.value_now(id))).collect()
    }

    /// The persistent state: every hashed symbol with its value(s), in hash order.
    /// The symbols the state hash covers, in hash order.
    pub(crate) fn hashed_ids(&self) -> &[usize] {
        &self.hashed
    }

    pub(crate) fn persistent(&self) -> Vec<(&str, Computed)> {
        self.hashed.iter().map(|id| (self.model.symbols[*id].name.as_str(), self.value_now(*id))).collect()
    }

    /// Overwrites the persistent state from a save. `values` must list the hashed symbols
    /// in hash order with the right type and shape.
    pub(crate) fn restore(&mut self, steps_done: u64, values: Vec<(String, Computed)>) -> Result<()> {
        let hashed = self.hashed.clone();
        if values.len() != hashed.len() {
            return model_err("the save file does not match this model's state");
        }
        for (id, (name, value)) in hashed.into_iter().zip(values) {
            let d = &self.model.symbols[id];
            let cells = match d.entity {
                Some(entity) => self.model.entities[entity].len(),
                None => self.model.cell_count(&d.dims),
            };
            let fits_declaration = match &value {
                Computed::One(v) => !d.columnar() && type_of(v) == d.ty,
                Computed::Each(column) if d.columnar() => {
                    column.len() == cells
                        && matches!(
                            (column, d.ty),
                            (Col::I(_), Ty::Int) | (Col::F(_), Ty::Real) | (Col::B(_), Ty::Bool)
                        )
                }
                _ => false,
            };
            if name != d.name || !fits_declaration {
                return model_err(format!("the save file does not match this model at {:?}", d.name));
            }
            self.store(id, value)?;
        }
        self.step = steps_done;
        self.sync_weights()?;
        self.remember();
        Ok(())
    }

    fn is_weight_state(&self, id: usize) -> bool {
        let name = &self.model.symbols[id].name;
        self.model.entities.iter().any(|e| e.weight_state.as_ref() == Some(name))
    }

    /// SHA-256 over everything needed to continue the run (engine contract, section 9).
    pub fn state_hash(&self) -> [u8; 32] {
        let mut digest = Sha256::new();
        digest.update(b"PSIM-STATE-v0\0");
        digest.update(self.step.to_le_bytes());
        let mut buffer: Vec<u8> = Vec::new();
        for &id in &self.hashed {
            let d = &self.model.symbols[id];
            digest.update(d.name.as_bytes());
            digest.update([0u8]);
            if !d.columnar() {
                match self.scal[id] {
                    Val::I(v) => digest.update(v.to_le_bytes()),
                    Val::F(v) => digest.update(v.to_bits().to_le_bytes()),
                    Val::B(v) => digest.update([v as u8]),
                }
                continue;
            }
            buffer.clear();
            match &self.cols[id] {
                Col::I(column) => column.iter().for_each(|v| buffer.extend_from_slice(&v.to_le_bytes())),
                Col::F(column) => column.iter().for_each(|v| buffer.extend_from_slice(&v.to_bits().to_le_bytes())),
                Col::B(column) => buffer.extend(column.iter().map(|v| *v as u8)),
            }
            digest.update(&buffer);
        }
        digest.finalize().into()
    }
}

impl crate::model::Scenario {
    /// The run this scenario describes.
    pub fn config(&self) -> RunConfig {
        RunConfig {
            seed: self.seed,
            preset: self.preset.clone(),
            params: self.params.clone(),
            levers: self.levers.clone(),
            commands: self.commands.clone(),
        }
    }
}

/// Checks that `raw` is a legal setting for the lever `name` of `model` without applying
/// it. Returns the value as it would be stored.
pub fn check_lever(model: &Model, name: &str, raw: &Value) -> Result<Val> {
    let d = match model.sym(name) {
        Some(d) if d.kind == Kind::Lever => d,
        _ => return model_err(format!("{name:?} is not a lever")),
    };
    let value = convert(Raw::Toml(raw), d.ty, d.money, model.minor, &format!("lever {name}"))?;
    let as_real = match value {
        Val::I(v) => v as f64,
        Val::F(v) => v,
        Val::B(v) => v as u8 as f64,
    };
    if !as_real.is_finite() || d.range.is_some_and(|(lo, hi)| !(lo <= as_real && as_real <= hi)) {
        return sim_err(format!("lever {name}: the value is outside its declared range"));
    }
    Ok(value)
}

fn too_large() -> Error {
    Error::Sim("a weighted total is too large to represent".to_string())
}

fn text_column(cells: &[String], d: &Decl, minor: i64, what: &str) -> Result<Col> {
    let mut column = match d.ty {
        Ty::Int => Col::I(Vec::with_capacity(cells.len())),
        Ty::Real => Col::F(Vec::with_capacity(cells.len())),
        Ty::Bool => Col::B(Vec::with_capacity(cells.len())),
    };
    for cell in cells {
        match (&mut column, convert(Raw::Text(cell), d.ty, d.money, minor, what)?) {
            (Col::I(c), Val::I(v)) => c.push(v),
            (Col::F(c), Val::F(v)) => c.push(v),
            (Col::B(c), Val::B(v)) => c.push(v),
            _ => unreachable!("convert returns the declared type"),
        }
    }
    Ok(column)
}

/// Per phase: vars and flows in dependency order, then the states updated there.
/// Format 1 (S4.4): compiles a weight state's rake. Returns it with the symbols it reads
/// this step (its targets among them) and those it reads through `prev()`.
fn compile_rake(m: &Model, d: &Decl) -> Result<(RakeProg, Vec<usize>, Vec<usize>)> {
    let rake = d.rake.as_ref().expect("a rake");
    let entity = d.entity.expect("weight states belong to an entity");
    let what = format!("state {} rake", d.name);
    let mut deps = std::collections::BTreeSet::new();
    let mut lagged = std::collections::BTreeSet::new();
    let mut take = |c: crate::program::Compiled| {
        deps.extend(c.deps);
        lagged.extend(c.lagged);
        c.prog
    };
    let when = take(compile_formula(m, &rake.when, None, &[], Ty::Bool, &Unit::one(), &format!("{what} when"))?);
    let mut margins = Vec::with_capacity(rake.margins.len());
    for (k, margin) in rake.margins.iter().enumerate() {
        let where_ = format!("{what} margin {}", k + 1);
        let target = m.sym_index[&margin.target];
        let t = &m.symbols[target];
        let mut dims = Vec::with_capacity(t.dims.len());
        let mut stride = 1usize;
        for &x in t.dims.iter().rev() {
            let dim = &m.dims[x];
            dims.push((dim.first.unwrap_or(0), dim.size(), stride));
            stride *= dim.size();
        }
        dims.reverse();
        let per_record = crate::units::div(&Some(t.unit.clone()), &Some(Unit::base(&m.entities[entity].name)));
        let mut slots = Vec::with_capacity(margin.slots.len());
        let mut constant = true;
        let mut take = |c: crate::program::Compiled| {
            constant &= c.lagged.is_empty()
                && c.deps.iter().all(|d| matches!(m.symbols[*d].kind, Kind::Param | Kind::Column))
                && fixed_program(&c.prog);
            take(c)
        };
        for slot in &margin.slots {
            let count = take(compile_formula(
                m,
                &slot.count,
                Some(entity),
                &[],
                Ty::Real,
                &per_record,
                &format!("{where_} count"),
            )?);
            let mut ats = Vec::with_capacity(slot.at.len());
            for (src, &x) in slot.at.iter().zip(&t.dims) {
                let label = format!("{where_} at {}", m.dims[x].name);
                ats.push(take(compile_formula(m, src, Some(entity), &[], Ty::Int, &Unit::one(), &label)?));
            }
            slots.push((count, ats));
        }
        margins.push(MarginProg { target, constant, cache: std::sync::OnceLock::new(), dims, cells: stride, slots });
    }
    deps.extend(margins.iter().map(|m| m.target));
    Ok((RakeProg { when, passes: rake.passes, margins }, deps.into_iter().collect(), lagged.into_iter().collect()))
}

/// A program whose result depends on nothing but what it names: no random draws, no
/// aggregates over records (whose weights change), no tables.
fn fixed_program(prog: &Program) -> bool {
    use crate::program::Op;
    prog.aggs.is_empty()
        && prog.aggs_by.is_empty()
        && prog.tables.is_empty()
        && prog.subs.iter().all(|s| fixed_program(&s.prog) && s.by.as_ref().is_none_or(|b| fixed_program(&b.key)))
        && !prog.ops.iter().any(|op| matches!(op, Op::Rand(..)))
}

fn plan(m: &Model, deps: &[Vec<usize>]) -> Result<Vec<Phase>> {
    let mut phases = Vec::with_capacity(m.phases.len());
    for p in 0..m.phases.len() {
        let in_phase = |kinds: &[Kind]| -> Vec<usize> {
            (0..m.symbols.len())
                .filter(|id| kinds.contains(&m.symbols[*id].kind) && m.symbols[*id].phase == Some(p))
                .collect()
        };
        let members = in_phase(&[Kind::Var, Kind::Flow]);
        let states = in_phase(&[Kind::State]);
        for &id in members.iter().chain(&states) {
            for &used in &deps[id] {
                let u = &m.symbols[used];
                if matches!(u.kind, Kind::Var | Kind::Flow) && u.phase > Some(p) {
                    return model_err(format!(
                        "{} (phase {}) reads {}, which is computed later (phase {}); use prev({}) or move it",
                        m.symbols[id].name,
                        m.phases[p],
                        u.name,
                        m.phases[u.phase.expect("vars and flows have a phase")],
                        u.name
                    ));
                }
            }
        }
        let mut order: Vec<usize> = Vec::with_capacity(members.len());
        let mut remaining = members.clone();
        while !remaining.is_empty() {
            let ready =
                remaining.iter().position(|id| deps[*id].iter().all(|u| order.contains(u) || !members.contains(u)));
            let Some(position) = ready else {
                let names: Vec<&str> = remaining.iter().map(|id| m.symbols[*id].name.as_str()).collect();
                return model_err(format!("circular dependency in phase {}: {}", m.phases[p], names.join(", ")));
            };
            order.push(remaining.remove(position)); // earliest declared among those that are ready
        }
        let mut level_of: HashMap<usize, usize> = HashMap::new();
        let mut levels: Vec<Vec<usize>> = Vec::new();
        for &id in &order {
            let level = deps[id].iter().filter_map(|u| level_of.get(u).map(|l| l + 1)).max().unwrap_or(0);
            level_of.insert(id, level);
            if levels.len() <= level {
                levels.resize(level + 1, Vec::new());
            }
            levels[level].push(id);
        }
        phases.push(Phase { order, states, levels });
    }
    Ok(phases)
}
