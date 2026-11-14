//! A game session: one run plus what a player needs around it.
//!
//! The session keeps the history of every result for charts, the latest and previous
//! values for screens that compare months, the policy changes the player made, and lever
//! changes waiting for the next step. It saves all of this in one file, so a loaded game
//! still has its charts. Tracing is always on, so any result can be explained.
//!
//! Session file, all integers little-endian, text as a `u16` length plus UTF-8:
//!
//! ```text
//! "PSIMSESS"   format u32 (4)
//! mods         version 3: u32 count; each mod the player chose beyond the scenario's own,
//!              as its folder (text)
//! engine save  u64 length + bytes (see save.rs)
//! commands     u32 count; step u64, lever text, raw value
//! changes      u32 count; step u64, lever text, value; version 2: passed u8, votes for
//!              u64, seats u64; version 4: flags u8 (1 a cost, 2 refused), cost f64
//! history      u32 name count, names; u32 step count; per step: step u64, hash 32 bytes;
//!              then per name, one f64 per step (NaN where the value did not exist)
//! latest       u32 count; name text, value          (values of the last step)
//! previous     u32 count; name text, value          (values of the step before)
//! ```
//!
//! A raw value is a tag (0 whole number, 1 real, 2 true/false, 3 text) and its bytes; a
//! value is a tag (0 whole number, 1 real, 2 true/false) and its bytes.

use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use toml::{Table as Toml, Value};

use crate::describe::Catalogue;
use crate::error::{Error, Result, model_err, sim_err};
use crate::explain::Explanation;
use crate::model::{Kind, Model, Scenario, load_model_with_mods, load_scenario_with_mods};
use crate::program::{Col, Val};
use crate::save::Migration;
use crate::sim::Simulation;
use crate::text::load_text;

const MAGIC: &[u8; 8] = b"PSIMSESS";
/// 0: before S4.5; 1 adds dimensioned values' cells (a version 0 game loads without them);
/// 2 adds each policy change's vote in the legislature (S5.4; older games count every
/// change as passed). 3 adds the mods chosen; 4 each change's cost in political capital and whether
/// it was refused (S12.4).
const SAVE_VERSION: u32 = 4;

/// A lever change that has taken effect.
#[derive(Clone, Debug, PartialEq)]
pub struct Change {
    pub step: u64,
    pub lever: String,
    pub value: Val,
    /// Format 1 (S5.4): false when the legislature voted the change down, so the lever kept
    /// its value. `votes_for` and `seats` are the vote (both 0 when there was none).
    pub passed: bool,
    pub votes_for: i64,
    pub seats: i64,
    /// Stage S12.4: what the bill cost in political capital (`None` without capital, or in
    /// a game saved before version 4), and whether it was refused for want of it.
    pub cost: Option<f64>,
    pub refused: bool,
}

/// Every result of every step, by name. Money is in minor units; true/false is 1 or 0.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct History {
    pub names: Vec<String>,
    pub steps: Vec<u64>,
    pub hashes: Vec<[u8; 32]>,
    /// Parallel to `names`; each holds one value per entry of `steps`.
    pub values: Vec<Vec<f64>>,
    index: HashMap<String, usize>,
}

impl History {
    pub fn series(&self, name: &str) -> Option<&[f64]> {
        self.index.get(name).map(|i| self.values[*i].as_slice())
    }

    fn push(&mut self, step: u64, hash: [u8; 32], row: &[(String, Val)]) {
        let length = self.steps.len();
        self.steps.push(step);
        self.hashes.push(hash);
        for (name, value) in row {
            let index = match self.index.get(name) {
                Some(i) => *i,
                None => {
                    self.index.insert(name.clone(), self.names.len());
                    self.names.push(name.clone());
                    self.values.push(vec![f64::NAN; length]);
                    self.names.len() - 1
                }
            };
            self.values[index].push(as_f64(value));
        }
        for column in &mut self.values {
            if column.len() == length {
                column.push(f64::NAN);
            }
        }
    }

    fn rebuild_index(&mut self) {
        self.index = self.names.iter().enumerate().map(|(i, n)| (n.clone(), i)).collect();
    }
}

pub fn as_f64(value: &Val) -> f64 {
    match value {
        Val::I(v) => *v as f64,
        Val::F(v) => *v,
        Val::B(v) => *v as u8 as f64,
    }
}

pub struct Session {
    scenario_path: PathBuf,
    scenario: Scenario,
    model: Arc<Model>,
    catalogue: Catalogue,
    sim: Simulation,
    changes: Vec<Change>,
    history: History,
    latest: BTreeMap<String, Val>,
    previous: BTreeMap<String, Val>,
    /// Format 1: each dimensioned var's and state's cells after the last step and the one before.
    latest_cells: BTreeMap<String, Vec<f64>>,
    previous_cells: BTreeMap<String, Vec<f64>>,
    /// A step failed part-way and its changes could not be undone.
    broken: bool,
    /// Stage S7.0: what loading the saved game into a changed model did, if it had changed.
    migration: Option<Migration>,
    /// Stage S7.1: mods the player chose beyond the scenario's own, by folder.
    extra_mods: Vec<PathBuf>,
    /// Stage S7.1: mods a loaded game had that could not be found, by folder.
    missing_mods: Vec<String>,
    /// Stage S7.4: the language of the game's words ("" for the model's own), and the
    /// scenario's `[play]` table as written, before any text was applied to it.
    language: String,
    play_written: Toml,
}

impl Session {
    /// Starts a new game from a scenario file.
    pub fn open(path: &Path) -> Result<Session> {
        Session::open_with_mods(path, &[])
    }

    /// Stage S7.1: starts a new game with mods the player chose, after the scenario's own.
    pub fn open_with_mods(path: &Path, mods: &[PathBuf]) -> Result<Session> {
        let scenario = load_scenario_with_mods(path, mods)?;
        let model = Arc::new(scenario.model.clone());
        let mut sim = Simulation::new(Arc::clone(&model), scenario.config())?;
        sim.set_tracing(true);
        let mut session = Session::assemble(path, scenario, model, sim);
        session.extra_mods = mods.to_vec();
        Ok(session)
    }

    fn assemble(path: &Path, scenario: Scenario, model: Arc<Model>, sim: Simulation) -> Session {
        let mut catalogue = Catalogue::of(&model);
        let (deps, lagged) = sim.dependencies();
        catalogue.link(&model, deps, lagged);
        let mut session = Session {
            scenario_path: path.to_path_buf(),
            scenario,
            model,
            catalogue,
            sim,
            changes: Vec::new(),
            history: History::default(),
            latest: BTreeMap::new(),
            previous: BTreeMap::new(),
            broken: false,
            latest_cells: BTreeMap::new(),
            previous_cells: BTreeMap::new(),
            migration: None,
            extra_mods: Vec::new(),
            missing_mods: Vec::new(),
            language: String::new(),
            play_written: Toml::new(),
        };
        session.play_written = session.scenario.play.clone();
        // Lever settings are known before any step.
        for entry in session.catalogue.entries.iter().filter(|e| e.kind == Kind::Lever) {
            if let Some(value) = session.sim.scalar(&entry.name) {
                session.latest.insert(entry.name.clone(), value);
            }
        }
        session
    }

    pub fn scenario(&self) -> &Scenario {
        &self.scenario
    }

    /// Stage S7.0: when this game was loaded from a save made with other model files, what
    /// was carried across and what started again.
    pub fn migration(&self) -> Option<&Migration> {
        self.migration.as_ref()
    }

    /// Stage S7.4: the language of the game's words: "" for the model's own.
    pub fn language(&self) -> &str {
        &self.language
    }

    /// Stage S7.4: puts the game's words (labels, help, the scenario's `[play]` text) in a
    /// language from the model's and its mods' `text/` folders, or back in the model's own
    /// with "". The run does not change.
    pub fn set_language(&mut self, language: &str) -> Result<()> {
        let previous = std::mem::replace(&mut self.language, language.to_string());
        if let Err(e) = self.relabel() {
            self.language = previous;
            return Err(e);
        }
        Ok(())
    }

    /// Builds the catalogue and the `[play]` table again, in the session's language.
    fn relabel(&mut self) -> Result<()> {
        let mut catalogue = Catalogue::of(&self.model);
        let (deps, lagged) = self.sim.dependencies();
        catalogue.link(&self.model, deps, lagged);
        let mut play = self.play_written.clone();
        if !self.language.is_empty() {
            let Some(text) = load_text(&self.model, &self.language)? else {
                return model_err(format!("this model has no text in {:?}", self.language));
            };
            text.apply(&mut catalogue);
            text.apply_play(&mut play, &self.scenario.name);
        }
        self.catalogue = catalogue;
        self.scenario.play = play;
        Ok(())
    }

    /// Stage S7.1: the mods the player chose beyond the scenario's own.
    pub fn extra_mods(&self) -> &[PathBuf] {
        &self.extra_mods
    }

    /// Stage S7.1: mods a loaded game was played with that are no longer where they were.
    pub fn missing_mods(&self) -> &[String] {
        &self.missing_mods
    }

    pub fn scenario_path(&self) -> &Path {
        &self.scenario_path
    }

    pub fn model(&self) -> &Model {
        &self.model
    }

    pub fn catalogue(&self) -> &Catalogue {
        &self.catalogue
    }

    pub fn simulation(&self) -> &Simulation {
        &self.sim
    }

    pub fn steps_done(&self) -> u64 {
        self.sim.steps_done()
    }

    pub fn history(&self) -> &History {
        &self.history
    }

    pub fn changes(&self) -> &[Change] {
        &self.changes
    }

    /// A value from the last completed step (levers: their current setting).
    pub fn latest(&self, name: &str) -> Option<Val> {
        self.latest.get(name).copied()
    }

    /// The same value one step earlier.
    /// Format 1: a dimensioned value's cells after the last step (row-major), as reals.
    pub fn cells(&self, name: &str) -> Option<&[f64]> {
        self.latest_cells.get(name).map(Vec::as_slice)
    }

    /// The same cells one step earlier.
    pub fn previous_cells(&self, name: &str) -> Option<&[f64]> {
        self.previous_cells.get(name).map(Vec::as_slice)
    }

    pub fn previous(&self, name: &str) -> Option<Val> {
        self.previous.get(name).copied()
    }

    /// Runs one step. If it fails, every value is put back as it was before the step, so
    /// the game can go on after the model is corrected and reloaded (or a lever changed).
    pub fn step(&mut self) -> Result<()> {
        if self.broken {
            return sim_err("a step failed part-way and could not be undone; load a saved game");
        }
        let index = self.sim.steps_done();
        let applying: Vec<(String, Val)> = self
            .sim
            .commands()
            .into_iter()
            .filter(|(step, _, _)| *step == index)
            .filter_map(|(_, lever, raw)| self.sim.check_lever(&lever, &raw).ok().map(|v| (lever, v)))
            .collect();
        let row = match self.sim.step() {
            Ok(row) => row,
            Err(error) => {
                self.broken = !self.sim.roll_back();
                return Err(error);
            }
        };
        let named: Vec<(String, Val)> = self.sim.row_names().iter().cloned().zip(row.values.iter().copied()).collect();
        self.history.push(row.step, row.hash, &named);
        self.previous = std::mem::take(&mut self.latest);
        self.previous_cells = std::mem::take(&mut self.latest_cells);
        for d in self.model.symbols.iter().filter(|d| !d.dims.is_empty() && matches!(d.kind, Kind::Var | Kind::State)) {
            if let Some(column) = self.sim.column(&d.name) {
                let values = match column {
                    Col::I(v) => v.iter().map(|x| *x as f64).collect(),
                    Col::F(v) => v.clone(),
                    Col::B(v) => v.iter().map(|x| *x as i64 as f64).collect(),
                };
                self.latest_cells.insert(d.name.clone(), values);
            }
        }
        self.latest = named.into_iter().collect();
        // Remove duplicates of one lever in one step: the last one is what applied.
        let mut seen: Vec<String> = Vec::new();
        for (lever, value) in applying.into_iter().rev() {
            if !seen.contains(&lever) {
                seen.push(lever.clone());
                let vote = self.sim.votes().iter().rev().find(|v| v.step == index && v.lever == lever);
                let (passed, votes_for, seats) = vote.map(|v| (v.passed, v.votes_for, v.seats)).unwrap_or((true, 0, 0));
                let (cost, refused) = vote.map(|v| (v.cost, v.refused)).unwrap_or((None, false));
                self.changes.push(Change { step: index, lever, value, passed, votes_for, seats, cost, refused });
            }
        }
        Ok(())
    }

    /// Schedules a lever change for the next step. Returns the value as it will be stored.
    pub fn set_lever(&mut self, name: &str, raw: Value) -> Result<Val> {
        let value = self.sim.check_lever(name, &raw)?;
        let next = self.sim.steps_done();
        let mut commands = self.sim.commands();
        commands.retain(|(step, lever, _)| !(*step == next && lever == name));
        commands.push((next, name.to_string(), raw));
        self.sim.set_commands(commands);
        Ok(value)
    }

    /// Stage S12.4: what any bill costs and what moving a lever across its range costs, if
    /// the model has political capital (see [`crate::bill_cost`]).
    pub fn capital_prices(&self) -> Option<(f64, f64)> {
        self.sim.capital_prices()
    }

    /// Withdraws a lever change scheduled for the next step.
    pub fn cancel_lever(&mut self, name: &str) {
        let next = self.sim.steps_done();
        let mut commands = self.sim.commands();
        commands.retain(|(step, lever, _)| !(*step == next && lever == name));
        self.sim.set_commands(commands);
    }

    /// Stage S9.1: the dilemmas open now with no answer scheduled for the next step, in
    /// the order declared. A game asks for these before it runs another month.
    pub fn unanswered_dilemmas(&self) -> Vec<String> {
        let next = self.sim.steps_done();
        let answered: Vec<String> =
            self.sim.commands().into_iter().filter(|(step, _, _)| *step == next).map(|(_, lever, _)| lever).collect();
        self.model
            .dilemmas
            .iter()
            .filter(|d| matches!(self.sim.scalar(&format!("{}_open", d.name)), Some(Val::B(true))))
            .filter(|d| !answered.contains(&d.name))
            .map(|d| d.name.clone())
            .collect()
    }

    /// Lever changes that will take effect in the next step.
    pub fn pending(&self) -> Vec<(String, Val)> {
        let next = self.sim.steps_done();
        let mut out: Vec<(String, Val)> = Vec::new();
        for (step, lever, raw) in self.sim.commands() {
            if step != next {
                continue;
            }
            if let Ok(value) = self.sim.check_lever(&lever, &raw) {
                out.retain(|(l, _)| *l != lever);
                out.push((lever, value));
            }
        }
        out
    }

    pub fn explain(&self, name: &str) -> Result<Explanation> {
        self.sim.explain(name)
    }

    /// Reads the model files again and continues the run on the new model. Returns the
    /// names of persistent values that started again from their initial value.
    pub fn reload(&mut self) -> Result<Vec<String>> {
        if self.broken {
            return sim_err("a step failed part-way and could not be undone; load a saved game");
        }
        // The same mods, read again too.
        let mods: Vec<PathBuf> = self.model.mods.iter().map(|m| m.dir.clone()).collect();
        let model = Arc::new(load_model_with_mods(&self.model.root, &mods)?);
        let (sim, reset) = self.sim.reload(Arc::clone(&model), &self.scenario.preset, self.scenario.params.clone())?;
        self.scenario.model = (*model).clone();
        self.model = model;
        self.sim = sim;
        // Stage S7.4: in the same language (its text may have changed too); if that text is
        // gone, the model's own words.
        if self.relabel().is_err() {
            self.language.clear();
            self.relabel()?;
        }
        Ok(reset)
    }

    // ------------------------------------------------------------------ files

    pub fn save(&self) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(MAGIC);
        out.extend_from_slice(&SAVE_VERSION.to_le_bytes());
        // Version 3: the mods the player chose.
        out.extend_from_slice(&(self.extra_mods.len() as u32).to_le_bytes());
        for dir in &self.extra_mods {
            put_text(&mut out, &dir.to_string_lossy());
        }
        let engine = self.sim.save();
        out.extend_from_slice(&(engine.len() as u64).to_le_bytes());
        out.extend_from_slice(&engine);

        let commands = self.sim.commands();
        out.extend_from_slice(&(commands.len() as u32).to_le_bytes());
        for (step, lever, raw) in &commands {
            out.extend_from_slice(&step.to_le_bytes());
            put_text(&mut out, lever);
            put_raw(&mut out, raw);
        }
        out.extend_from_slice(&(self.changes.len() as u32).to_le_bytes());
        for change in &self.changes {
            out.extend_from_slice(&change.step.to_le_bytes());
            put_text(&mut out, &change.lever);
            put_val(&mut out, &change.value);
            // Version 2: the vote.
            out.push(u8::from(change.passed));
            out.extend_from_slice(&change.votes_for.to_le_bytes());
            out.extend_from_slice(&change.seats.to_le_bytes());
            // Version 4: whether it has a cost (bit 0) and was refused (bit 1), and the cost.
            out.push(u8::from(change.cost.is_some()) | (u8::from(change.refused) << 1));
            out.extend_from_slice(&change.cost.unwrap_or(0.0).to_bits().to_le_bytes());
        }
        let h = &self.history;
        out.extend_from_slice(&(h.names.len() as u32).to_le_bytes());
        for name in &h.names {
            put_text(&mut out, name);
        }
        out.extend_from_slice(&(h.steps.len() as u32).to_le_bytes());
        for (step, hash) in h.steps.iter().zip(&h.hashes) {
            out.extend_from_slice(&step.to_le_bytes());
            out.extend_from_slice(hash);
        }
        for column in &h.values {
            for v in column {
                out.extend_from_slice(&v.to_bits().to_le_bytes());
            }
        }
        for map in [&self.latest, &self.previous] {
            out.extend_from_slice(&(map.len() as u32).to_le_bytes());
            for (name, value) in map {
                put_text(&mut out, name);
                put_val(&mut out, value);
            }
        }
        // Version 1: dimensioned values' cells after the last step and the one before.
        for map in [&self.latest_cells, &self.previous_cells] {
            out.extend_from_slice(&(map.len() as u32).to_le_bytes());
            for (name, cells) in map {
                put_text(&mut out, name);
                out.extend_from_slice(&(cells.len() as u64).to_le_bytes());
                for v in cells {
                    out.extend_from_slice(&v.to_bits().to_le_bytes());
                }
            }
        }
        out
    }

    /// Continues a saved game. `path` is the scenario the game was started from. When its
    /// model files have changed since the save, the game continues on the new model with
    /// what still fits (stage S7.0; [`Session::migration`] says what).
    pub fn load(path: &Path, bytes: &[u8]) -> Result<Session> {
        let mut r = Reader { bytes, pos: 0 };
        if r.take(8)? != MAGIC {
            return model_err("this is not a PoliSim saved game");
        }
        let version = r.u32()?;
        if version > SAVE_VERSION {
            return model_err("this saved game was made by a newer version");
        }
        let mut extra_mods = Vec::new();
        let mut missing_mods = Vec::new();
        for _ in 0..if version >= 3 { r.u32()? } else { 0 } {
            let dir = PathBuf::from(r.text()?);
            // A mod that is gone is left out: migration carries what still fits.
            if dir.join("mod.toml").is_file() {
                extra_mods.push(dir);
            } else {
                missing_mods.push(dir.to_string_lossy().into_owned());
            }
        }
        let length = usize::try_from(r.u64()?).map_err(|_| damaged())?;
        let engine = r.take(length)?;
        let scenario = load_scenario_with_mods(path, &extra_mods)?;
        let model = Arc::new(scenario.model.clone());
        let (mut sim, migration) =
            Simulation::migrate(Arc::clone(&model), engine, &scenario.preset, scenario.params.clone())?;
        let mut commands = Vec::new();
        for _ in 0..r.u32()? {
            let step = r.u64()?;
            let lever = r.text()?;
            let raw = r.raw()?;
            // A lever the model no longer has drops its scheduled changes.
            if model.sym(&lever).is_some_and(|d| d.kind == Kind::Lever) {
                commands.push((step, lever, raw));
            }
        }
        sim.set_commands(commands);
        sim.set_tracing(true);
        let mut session = Session::assemble(path, scenario, Arc::clone(&model), sim);
        for _ in 0..r.u32()? {
            let step = r.u64()?;
            let lever = r.text()?;
            let value = r.val()?;
            let (passed, votes_for, seats) =
                if version >= 2 { (r.take(1)?[0] != 0, r.u64()? as i64, r.u64()? as i64) } else { (true, 0, 0) };
            let (cost, refused) = if version >= 4 {
                let flags = r.take(1)?[0];
                let cost = f64::from_bits(r.u64()?);
                ((flags & 1 != 0).then_some(cost), flags & 2 != 0)
            } else {
                (None, false)
            };
            session.changes.push(Change { step, lever, value, passed, votes_for, seats, cost, refused });
        }
        let mut history = History::default();
        for _ in 0..r.u32()? {
            history.names.push(r.text()?);
        }
        let steps = r.u32()? as usize;
        if steps > bytes.len() {
            return Err(damaged());
        }
        for _ in 0..steps {
            history.steps.push(r.u64()?);
            history.hashes.push(r.take(32)?.try_into().expect("32 bytes"));
        }
        for _ in 0..history.names.len() {
            let mut column = Vec::with_capacity(steps);
            for _ in 0..steps {
                column.push(f64::from_bits(r.u64()?));
            }
            history.values.push(column);
        }
        history.rebuild_index();
        session.history = history;
        for which in 0..2 {
            let mut map = BTreeMap::new();
            for _ in 0..r.u32()? {
                let name = r.text()?;
                map.insert(name, r.val()?);
            }
            if which == 0 {
                session.latest = map;
            } else {
                session.previous = map;
            }
        }
        for which in 0..u32::from(version >= 1) * 2 {
            let mut map = BTreeMap::new();
            for _ in 0..r.u32()? {
                let name = r.text()?;
                let count = usize::try_from(r.u64()?).map_err(|_| damaged())?;
                if count > bytes.len() {
                    return Err(damaged());
                }
                let mut cells = Vec::with_capacity(count);
                for _ in 0..count {
                    cells.push(f64::from_bits(r.u64()?));
                }
                map.insert(name, cells);
            }
            if which == 0 {
                session.latest_cells = map;
            } else {
                session.previous_cells = map;
            }
        }
        if r.pos != bytes.len() {
            return Err(damaged());
        }
        if migration.is_some() {
            // Shown values the model no longer has go; levers show their carried setting.
            let known = |name: &String| model.sym_index.contains_key(name);
            session.latest.retain(|name, _| known(name));
            session.previous.retain(|name, _| known(name));
            session.latest_cells.retain(|name, _| known(name));
            session.previous_cells.retain(|name, _| known(name));
            for entry in session.catalogue.entries.iter().filter(|e| e.kind == Kind::Lever) {
                if let Some(value) = session.sim.scalar(&entry.name) {
                    session.latest.insert(entry.name.clone(), value);
                }
            }
        }
        session.migration = migration;
        session.extra_mods = extra_mods;
        session.missing_mods = missing_mods;
        Ok(session)
    }
}

fn damaged() -> Error {
    Error::Model("the saved game is damaged".to_string())
}

fn put_text(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(&(text.len() as u16).to_le_bytes());
    out.extend_from_slice(text.as_bytes());
}

fn put_val(out: &mut Vec<u8>, value: &Val) {
    match value {
        Val::I(v) => {
            out.push(0);
            out.extend_from_slice(&v.to_le_bytes());
        }
        Val::F(v) => {
            out.push(1);
            out.extend_from_slice(&v.to_bits().to_le_bytes());
        }
        Val::B(v) => out.extend_from_slice(&[2, *v as u8]),
    }
}

fn put_raw(out: &mut Vec<u8>, raw: &Value) {
    match raw {
        Value::Integer(v) => {
            out.push(0);
            out.extend_from_slice(&v.to_le_bytes());
        }
        Value::Float(v) => {
            out.push(1);
            out.extend_from_slice(&v.to_bits().to_le_bytes());
        }
        Value::Boolean(v) => out.extend_from_slice(&[2, *v as u8]),
        other => {
            out.push(3);
            put_text(out, other.as_str().unwrap_or_default());
        }
    }
}

struct Reader<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn take(&mut self, count: usize) -> Result<&'a [u8]> {
        let end = self.pos.checked_add(count).filter(|e| *e <= self.bytes.len()).ok_or_else(damaged)?;
        let slice = &self.bytes[self.pos..end];
        self.pos = end;
        Ok(slice)
    }

    fn u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().expect("4 bytes")))
    }

    fn u64(&mut self) -> Result<u64> {
        Ok(u64::from_le_bytes(self.take(8)?.try_into().expect("8 bytes")))
    }

    fn text(&mut self) -> Result<String> {
        let length = u16::from_le_bytes(self.take(2)?.try_into().expect("2 bytes")) as usize;
        String::from_utf8(self.take(length)?.to_vec()).map_err(|_| damaged())
    }

    fn val(&mut self) -> Result<Val> {
        match self.take(1)?[0] {
            0 => Ok(Val::I(self.u64()? as i64)),
            1 => Ok(Val::F(f64::from_bits(self.u64()?))),
            2 => Ok(Val::B(self.take(1)?[0] != 0)),
            _ => Err(damaged()),
        }
    }

    fn raw(&mut self) -> Result<Value> {
        match self.take(1)?[0] {
            0 => Ok(Value::Integer(self.u64()? as i64)),
            1 => Ok(Value::Float(f64::from_bits(self.u64()?))),
            2 => Ok(Value::Boolean(self.take(1)?[0] != 0)),
            3 => Ok(Value::String(self.text()?)),
            _ => Err(damaged()),
        }
    }
}
