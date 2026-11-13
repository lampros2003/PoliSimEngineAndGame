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

use std::collections::BTreeMap;
use std::sync::Arc;

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
}

struct Phase {
    order: Vec<usize>,
    states: Vec<usize>,
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

impl Simulation {
    pub fn new(model: Arc<Model>, config: RunConfig) -> Result<Simulation> {
        let count = model.symbols.len();
        let mut simulation = Simulation {
            model: Arc::clone(&model),
            seed: config.seed,
            step: 0,
            scal: vec![Val::I(0); count],
            cols: vec![Col::I(Vec::new()); count],
            prev_scal: vec![Val::I(0); count],
            prev_cols: vec![Col::I(Vec::new()); count],
            progs: vec![None; count],
            plan: Vec::new(),
            lagged: vec![false; count],
            hashed: Vec::new(),
            commands: schedule(config.commands),
            flow_totals: vec![0; model.flows.len()],
            row_names: Vec::new(),
            row_sources: Vec::new(),
        };
        let m = &*model;
        let minor = m.minor;

        // ---- parameters, levers, data columns
        let mut overrides = config.params;
        for (id, d) in m.symbols.iter().enumerate() {
            match d.kind {
                Kind::Param => {
                    let what = format!("param {}", d.name);
                    let given = overrides.iter().position(|(name, _)| *name == d.name).map(|i| overrides.remove(i).1);
                    let raw = match given.as_ref().or_else(|| d.spec.get("value")).or_else(|| d.spec.get(&config.preset)) {
                        Some(raw) => raw,
                        None => return model_err(format!("{what}: no 'value' and no {:?} preset", config.preset)),
                    };
                    let value = convert(Raw::Toml(raw), d.ty, d.money, minor, &what)?;
                    simulation.store(id, Computed::One(value))?;
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
        let mut lever_overrides = config.levers;
        for d in m.symbols.iter().filter(|d| d.kind == Kind::Lever) {
            let given = lever_overrides.iter().position(|(name, _)| *name == d.name).map(|i| lever_overrides.remove(i).1);
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

        // ---- compile formulas and build the evaluation plan
        let mut deps: Vec<Vec<usize>> = vec![Vec::new(); count];
        for (id, d) in m.symbols.iter().enumerate() {
            let Some(expr) = &d.expr else { continue };
            let label = format!("{} {}{}", d.kind.name(), d.name, if d.kind == Kind::State { " (next)" } else { "" });
            let compiled = compile_formula(m, expr, d.entity, d.ty, &d.unit, &label)?;
            for lagged in compiled.lagged {
                simulation.lagged[lagged] = true;
            }
            deps[id] = compiled.deps;
            simulation.progs[id] = Some(compiled.prog);
        }
        simulation.plan = plan(m, &deps)?;

        // ---- values that prev() sees during the first step
        let mut lagged: Vec<usize> = (0..count).filter(|id| simulation.lagged[*id]).collect();
        lagged.sort_by(|a, b| m.symbols[*a].name.cmp(&m.symbols[*b].name));
        for id in lagged {
            let d = &m.symbols[id];
            if matches!(d.kind, Kind::Var | Kind::Flow) {
                if d.initial.is_none() {
                    return model_err(format!("{} {} is read through prev() and needs 'initial'", d.kind.name(), d.name));
                }
                let value = simulation.initial(d)?;
                simulation.store(id, value)?;
            }
        }
        simulation.remember();

        simulation.hashed = (0..count)
            .filter(|id| matches!(m.symbols[*id].kind, Kind::Lever | Kind::Account | Kind::State) || simulation.lagged[*id])
            .collect();
        simulation.hashed.sort_by(|a, b| m.symbols[*a].name.cmp(&m.symbols[*b].name));

        for (id, d) in m.symbols.iter().enumerate() {
            if d.kind == Kind::Param {
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
        let fail = |shown: String| -> Result<()> { sim_err(format!("{} {}: {shown} is outside its declared range", d.kind.name(), d.name)) };
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
        for (w, v) in self.model.entities[entity].weights.iter().zip(int_column(&self.cols[id])) {
            total = total.checked_add(*w as i128 * *v as i128).ok_or_else(too_large)?;
        }
        Ok(total)
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

    fn remember(&mut self) {
        for id in 0..self.lagged.len() {
            if self.lagged[id] {
                if self.model.symbols[id].entity.is_none() {
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
            seed: self.seed,
            step: self.step as u32,
        }
    }

    fn compute(&self, id: usize) -> Result<Computed> {
        let d = &self.model.symbols[id];
        let prog = self.progs[id].as_ref().expect("planned symbols have a program");
        let named = |message: String| Error::Sim(format!("{} {}: {message}", d.kind.name(), d.name));
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
        self.record()
    }

    fn step_inner(&mut self) -> Result<()> {
        if let Some(commands) = self.commands.get(&self.step).cloned() {
            for (lever, raw) in commands {
                self.set_lever(&lever, &raw)?;
            }
        }
        for phase in 0..self.plan.len() {
            for position in 0..self.plan[phase].order.len() {
                let id = self.plan[phase].order[position];
                let value = self.compute(id)?;
                self.store(id, value)?;
            }
            let mut pending = Vec::with_capacity(self.plan[phase].states.len());
            for &id in &self.plan[phase].states {
                pending.push((id, self.compute(id)?));
            }
            for (id, value) in pending {
                self.store(id, value)?;
            }
        }
        self.post_flows()
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
                    for (w, a) in m.entities[entity].weights.iter().zip(amounts) {
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
            let sum: i128 = m.accounts.iter().zip(&totals).filter(|(a, _)| a.instrument == index).map(|(_, t)| *t).sum();
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
            });
        }
        Ok(Row { step: self.step - 1, hash: self.state_hash(), values })
    }

    /// Current per-record values of a symbol.
    pub fn column(&self, name: &str) -> Option<&Col> {
        let id = *self.model.sym_index.get(name)?;
        self.model.symbols[id].entity.map(|_| &self.cols[id])
    }

    /// Current national value of a symbol.
    pub fn scalar(&self, name: &str) -> Option<Val> {
        let id = *self.model.sym_index.get(name)?;
        if self.model.symbols[id].entity.is_some() {
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
        let compiled = compile_formula(&self.model, src, ctx, ty, &unit, "evaluate")?;
        let cx = EvalCtx { prev_scal: &self.scal, prev_cols: &self.cols, ..self.ctx() };
        match ctx {
            None => vm::eval_scalar(&compiled.prog, &cx).map(Computed::One).map_err(Error::Sim),
            Some(entity) => vm::eval_column(&compiled.prog, entity, &cx).map(Computed::Each).map_err(Error::Sim),
        }
    }

    /// Symbols in the state hash, in hash order.
    pub(crate) fn hashed_symbols(&self) -> &[usize] {
        &self.hashed
    }

    pub(crate) fn value_of(&self, id: usize) -> Computed {
        match self.model.symbols[id].entity {
            None => Computed::One(self.scal[id]),
            Some(_) => Computed::Each(self.cols[id].clone()),
        }
    }

    /// Overwrites persistent state from a save. `values` is parallel to `hashed_symbols`.
    pub(crate) fn restore(&mut self, steps_done: u64, values: Vec<Computed>) -> Result<()> {
        let hashed = self.hashed.clone();
        if values.len() != hashed.len() {
            return model_err("save file does not match this model's state");
        }
        for (id, value) in hashed.into_iter().zip(values) {
            self.store(id, value)?;
        }
        self.step = steps_done;
        self.remember();
        Ok(())
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
            if d.entity.is_none() {
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
fn plan(m: &Model, deps: &[Vec<usize>]) -> Result<Vec<Phase>> {
    let mut phases = Vec::with_capacity(m.phases.len());
    for p in 0..m.phases.len() {
        let in_phase = |kinds: &[Kind]| -> Vec<usize> {
            (0..m.symbols.len()).filter(|id| kinds.contains(&m.symbols[*id].kind) && m.symbols[*id].phase == Some(p)).collect()
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
            let ready = remaining.iter().position(|id| deps[*id].iter().all(|u| order.contains(u) || !members.contains(u)));
            let Some(position) = ready else {
                let names: Vec<&str> = remaining.iter().map(|id| m.symbols[*id].name.as_str()).collect();
                return model_err(format!("circular dependency in phase {}: {}", m.phases[p], names.join(", ")));
            };
            order.push(remaining.remove(position)); // earliest declared among those that are ready
        }
        phases.push(Phase { order, states });
    }
    Ok(phases)
}
