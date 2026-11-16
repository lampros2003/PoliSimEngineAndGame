//! The bridge between the PoliSim engine and the Godot game client.
//!
//! GDScript sees one class, `PoliSim`. The game session runs on a worker thread owned by
//! this library; the interface thread sends it requests and reads a mirror of the
//! session's state that the worker refreshes after every request (stage S14.3: with what
//! changed only, so a request costs the same in the first month and the hundredth). No
//! Godot object is ever touched off the main thread, and a slow step never blocks the
//! window. Forecasts and the effects table run on threads of their own (stage S14.3), so
//! the next month never waits for them.
//!
//! Units: values read back are as the engine stores them (money in minor units, such as
//! pence). Lever settings are written as a person types them (money in major units).

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;

use godot::prelude::*;
use polisim_core::describe::Catalogue;
use polisim_core::model::Kind;
use polisim_core::session::{Change, Effect, Forecast, History, MIRRORED_CELLS, Outlook, Record};
use polisim_core::{Chamber, Explanation, Link, Migration, Model, Num, RawValue, Session, Ty, Val, check_lever, pyfmt};

struct PoliSimExtension;

#[gdextension]
unsafe impl ExtensionLibrary for PoliSimExtension {}

// ---------------------------------------------------------------------------- worker

enum Request {
    Step(u64),
    SetLever(String, RawValue),
    CancelLever(String),
    Explain(String),
    Save(PathBuf),
    Load(PathBuf),
    Reload,
    /// Stage S13.1: lever changes (as typed), months, tag.
    Forecast(Vec<(String, RawValue)>, u64, String),
    /// Stage S13.1: levers (stage S14.3: in the order they are to be done), months.
    Effects(Vec<String>, u64),
    /// Stage S13.1: entity, condition, count, columns, tag.
    Records(String, String, usize, Vec<String>, String),
}

/// Stage S14.3: how many levers of the effects table are computed at a time: every core
/// but one (left for the game's own month and the interface), at most sixteen.
fn effect_threads() -> usize {
    std::thread::available_parallelism().map_or(2, |n| n.get()).saturating_sub(1).clamp(1, 16)
}

/// Stage S14.3: an effects table: generation, months, effects so far, complete.
type Table = (u64, u64, Vec<Effect>, bool);

/// Stage S14.3: what the threads that look ahead share with the worker and the interface.
#[derive(Default)]
struct Looks {
    /// Bumped by a month, a load, a reload, a new game and closing: forecasts stop.
    month: AtomicU64,
    /// Bumped by those and by every lever change: what an "as is" branch starts from.
    state: AtomicU64,
    /// The newest forecast asked for; older ones stop.
    forecast: AtomicU64,
    /// Forecasts running: the effects table waits for them between months.
    forecasting: AtomicUsize,
    /// The last "as is" branch run: state, months, outlook. A forecast and the effects
    /// table of the same game share it.
    as_is: Mutex<Option<(u64, u64, Outlook)>>,
    /// The last effects table: its generation, months, effects so far, and whether it is
    /// complete (a save keeps a complete one of the game as it is).
    table: Mutex<Option<Table>>,
}

impl Looks {
    fn as_is(&self, state: u64, months: u64) -> Option<Outlook> {
        let held = self.as_is.lock().ok()?;
        held.as_ref().filter(|(s, m, _)| *s == state && *m == months).map(|(_, _, o)| o.clone())
    }

    fn keep_as_is(&self, state: u64, months: u64, outlook: &Outlook) {
        if let Ok(mut held) = self.as_is.lock()
            && self.state.load(Ordering::SeqCst) == state
        {
            *held = Some((state, months, outlook.clone()));
        }
    }
}

/// Stage S14.3: counts a forecast as running until it ends, even by a panic.
struct Running(Arc<Looks>);

impl Running {
    fn start(looks: &Arc<Looks>) -> Running {
        looks.forecasting.fetch_add(1, Ordering::SeqCst);
        Running(Arc::clone(looks))
    }
}

impl Drop for Running {
    fn drop(&mut self) {
        self.0.forecasting.fetch_sub(1, Ordering::SeqCst);
    }
}

/// What the interface may read without asking the worker.
#[derive(Clone, Default)]
struct View {
    steps_done: u64,
    latest: BTreeMap<String, Val>,
    previous: BTreeMap<String, Val>,
    pending: Vec<(String, Val)>,
    changes: Vec<Change>,
    history: History,
    failed: Option<String>,
    /// Format 1: one-dimensional values' cells after the last step and the one before.
    cells: BTreeMap<String, (Vec<f64>, Vec<f64>)>,
    /// Stage S12.4: what any bill costs and what a whole-range move costs, with capital.
    capital_prices: Option<(f64, f64)>,
    /// Stage S13.1: what a vote reads, so `vote_preview` never waits for the worker.
    chamber: Option<Chamber>,
}

/// Sent when the model changes: on opening, loading and reloading.
struct ModelInfo {
    model: Arc<Model>,
    catalogue: Catalogue,
}

/// Stage S14.3: what a month changes in the mirror.
struct MonthState {
    latest: BTreeMap<String, Val>,
    previous: BTreeMap<String, Val>,
    cells: BTreeMap<String, (Vec<f64>, Vec<f64>)>,
    capital_prices: Option<(f64, f64)>,
    chamber: Option<Chamber>,
}

/// Stage S14.3: the mirror's change after a request: always the small parts; what a month
/// changes only when a month has run (or the game was loaded or reloaded); the history and
/// the changes either appended to the copy the interface keeps or, after a load or reload,
/// in place of it.
struct Update {
    steps_done: u64,
    pending: Vec<(String, Val)>,
    failed: Option<String>,
    month: Option<Box<MonthState>>,
    reset: bool,
    history: History,
    changes: Vec<Change>,
}

impl View {
    fn apply(&mut self, u: Update) {
        self.steps_done = u.steps_done;
        self.pending = u.pending;
        self.failed = u.failed;
        if let Some(m) = u.month {
            let m = *m;
            (self.latest, self.previous, self.cells) = (m.latest, m.previous, m.cells);
            (self.capital_prices, self.chamber) = (m.capital_prices, m.chamber);
        }
        if u.reset {
            self.history = u.history;
            self.changes = u.changes;
        } else {
            self.history.append(u.history);
            self.changes.extend(u.changes);
        }
    }
}

/// Stage S14.3: how much of the session the interface's mirror already has.
struct Sent {
    history: usize,
    changes: usize,
    steps_done: u64,
}

impl Sent {
    fn of(session: &Session) -> Sent {
        Sent {
            history: session.history().steps.len(),
            changes: session.changes().len(),
            steps_done: session.steps_done(),
        }
    }

    fn update(&mut self, session: &Session, failed: &Option<String>, reset: bool) -> Update {
        let reset = reset || session.history().steps.len() < self.history || session.changes().len() < self.changes;
        let (history, changes) = if reset { (0, 0) } else { (self.history, self.changes) };
        let month = (reset || session.steps_done() != self.steps_done).then(|| Box::new(month_state(session)));
        let update = Update {
            steps_done: session.steps_done(),
            pending: session.pending(),
            failed: failed.clone(),
            month,
            reset,
            history: if reset { session.history().clone() } else { session.history().tail(history) },
            changes: session.changes()[changes..].to_vec(),
        };
        *self = Sent::of(session);
        update
    }
}

enum Reply {
    Update(Box<Update>),
    Model(Box<ModelInfo>),
    Event(EventData),
}

enum EventData {
    Stepped {
        count: u64,
    },
    Failed(String),
    Explained {
        name: String,
        result: Result<Box<Explanation>, String>,
    },
    Saved {
        path: String,
        error: Option<String>,
    },
    Loaded {
        migration: Option<Migration>,
        missing_mods: Vec<String>,
        error: Option<String>,
    },
    Reloaded {
        reset: Vec<String>,
        error: Option<String>,
    },
    /// Stage S13.1.
    Forecast {
        tag: String,
        months: u64,
        result: Result<Box<Forecast>, String>,
    },
    /// Stage S13.1: one lever of an effects table, and the end of one, each with the
    /// generation of the game it was computed for (older ones are dropped in `poll`).
    Effect {
        generation: u64,
        effect: Box<Effect>,
    },
    EffectsDone {
        generation: u64,
        count: u64,
    },
    Records {
        tag: String,
        result: Result<Vec<Record>, String>,
    },
}

/// The whole mirror, for a new game.
fn view_of(session: &Session) -> View {
    let mut view = View::default();
    view.apply(Sent::of(session).update(session, &None, true));
    view
}

fn month_state(session: &Session) -> MonthState {
    let catalogue = session.catalogue();
    let mut latest = BTreeMap::new();
    let mut previous = BTreeMap::new();
    let mut cells = BTreeMap::new();
    for entry in catalogue.entries.iter().filter(|e| e.dims.len() == 1) {
        let short = catalogue.dims.iter().any(|d| d.name == entry.dims[0] && d.labels.len() <= MIRRORED_CELLS);
        if let (true, Some(now)) = (short, session.cells(&entry.name)) {
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
    MonthState {
        latest,
        previous,
        cells,
        capital_prices: session.capital_prices(),
        chamber: session.simulation().chamber(),
    }
}

/// Stage S7.1: a scenario file as the start screen lists it, if it has a `[play] title`.
fn scenario_entry(path: &std::path::Path) -> Option<VarDictionary> {
    let doc: polisim_core::RawTable = std::fs::read_to_string(path).ok()?.parse().ok()?;
    let play = doc.get("play")?.as_table()?;
    let title = play.get("title")?.as_str()?;
    let model = doc.get("scenario")?.as_table()?.get("model")?.as_str()?;
    let manifest = path.parent()?.join(model).join("model.toml");
    let head: polisim_core::RawTable = std::fs::read_to_string(manifest).ok()?.parse().ok()?;
    let id = head.get("model")?.as_table()?.get("id")?.as_str()?;
    let mut d = VarDictionary::new();
    d.set("path", path.to_string_lossy().as_ref());
    d.set("title", title);
    d.set("country", play.get("country").and_then(|c| c.as_str()).unwrap_or(title));
    d.set("start", play.get("start").and_then(|c| c.as_str()).unwrap_or(""));
    d.set("summary", play.get("summary").and_then(|c| c.as_str()).unwrap_or(""));
    d.set("model", id);
    // Stage S7.4: the languages the model has text in, without loading it.
    let mut languages = VarArray::new();
    let mut found: Vec<(String, String)> = Vec::new();
    for file in std::fs::read_dir(path.parent()?.join(model).join("text")).into_iter().flatten().flatten() {
        let file = file.path();
        if file.extension().is_none_or(|e| e != "toml") {
            continue;
        }
        let code = file.file_stem()?.to_string_lossy().into_owned();
        let name = std::fs::read_to_string(&file)
            .ok()
            .and_then(|t| t.parse::<polisim_core::RawTable>().ok())
            .and_then(|t| t.get("text").and_then(|h| h.get("name")).and_then(|n| n.as_str()).map(str::to_string))
            .unwrap_or_else(|| code.clone());
        found.push((code, name));
    }
    found.sort();
    for (code, name) in found {
        let mut l = VarDictionary::new();
        l.set("code", code.as_str());
        l.set("name", name.as_str());
        languages.push(&l.to_variant());
    }
    d.set("languages", &languages);
    Some(d)
}

fn model_info(session: &Session) -> ModelInfo {
    ModelInfo { model: Arc::new(session.model().clone()), catalogue: session.catalogue().clone() }
}

fn worker(
    mut session: Session,
    requests: Receiver<Request>,
    replies: Sender<Reply>,
    outstanding: Arc<AtomicUsize>,
    generation: Arc<AtomicU64>,
    looks: Arc<Looks>,
) {
    // Stage S7.4: a loaded game keeps the language the game was opened in.
    let language = session.language().to_string();
    let mut failed: Option<String> = None;
    let mut sent = Sent::of(&session);
    let mut work = Work { replies: replies.clone(), generation, looks, table: None, send_saved: false };
    for request in requests {
        let mut reset = matches!(request, Request::Load(_) | Request::Reload);
        // Stage S10: a panic in the engine must not leave the game waiting for a thread that
        // has died. It is caught, the run is marked failed (loading a save or reloading the
        // model recovers), and the player is told.
        let handled = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            handle(&mut session, request, &mut failed, &language, &mut work)
        }));
        let event = match handled {
            Ok(event) => event,
            Err(payload) => {
                reset = true;
                let what = payload
                    .downcast_ref::<&str>()
                    .map(|s| s.to_string())
                    .or_else(|| payload.downcast_ref::<String>().cloned())
                    .unwrap_or_else(|| "unknown".to_string());
                let message = format!("internal error in the engine ({what}); load a saved game or reload the model");
                failed = Some(message.clone());
                Some(EventData::Failed(message))
            }
        };
        let _ = replies.send(Reply::Update(Box::new(sent.update(&session, &failed, reset))));
        if let Some(event) = event {
            let _ = replies.send(Reply::Event(event));
        }
        // Stage S14.3: a loaded game's saved effects table, after the `loaded` event.
        if std::mem::take(&mut work.send_saved) {
            work.saved_table(&session);
        }
        outstanding.fetch_sub(1, Ordering::SeqCst);
    }
}

/// One request on the worker thread: what it changes, and the event to report.
fn handle(
    session: &mut Session,
    request: Request,
    failed: &mut Option<String>,
    language: &str,
    work: &mut Work,
) -> Option<EventData> {
    {
        match request {
            Request::Step(count) => {
                // Stage S13.1: effects computed for the month before are stale.
                work.new_month();
                let mut done = 0;
                let mut error = None;
                if let Some(message) = failed.as_ref() {
                    error = Some(message.clone());
                } else {
                    for _ in 0..count {
                        // Stage S9.1: a month does not run while a dilemma awaits an answer.
                        if !session.unanswered_dilemmas().is_empty() {
                            break;
                        }
                        match session.step() {
                            Ok(()) => done += 1,
                            Err(e) => {
                                error = Some(e.to_string());
                                *failed = error.clone();
                                break;
                            }
                        }
                    }
                }
                match error {
                    Some(message) => Some(EventData::Failed(message)),
                    None => Some(EventData::Stepped { count: done }),
                }
            }
            Request::SetLever(name, raw) => {
                // Already checked on the interface thread; a refusal here changes nothing.
                let _ = session.set_lever(&name, raw);
                work.lever_changed(session, &name)
            }
            Request::CancelLever(name) => {
                session.cancel_lever(&name);
                work.lever_changed(session, &name)
            }
            Request::Explain(name) => {
                let result = session.explain(&name).map(Box::new).map_err(|e| e.to_string());
                Some(EventData::Explained { name, result })
            }
            Request::Save(path) => {
                work.keep_table(session);
                let error = std::fs::write(&path, session.save()).err().map(|e| e.to_string());
                Some(EventData::Saved { path: path.display().to_string(), error })
            }
            Request::Load(path) => {
                let loaded = std::fs::read(&path)
                    .map_err(|e| format!("cannot read {}: {e}", path.display()))
                    .and_then(|bytes| Session::load(session.scenario_path(), &bytes).map_err(|e| e.to_string()));
                match loaded {
                    Ok(mut next) => {
                        if !language.is_empty() {
                            let _ = next.set_language(language);
                        }
                        *session = next;
                        *failed = None;
                        work.new_month();
                        let _ = work.replies.send(Reply::Model(Box::new(model_info(session))));
                        work.send_saved = true;
                        Some(EventData::Loaded {
                            migration: session.migration().cloned(),
                            missing_mods: session.missing_mods().to_vec(),
                            error: None,
                        })
                    }
                    Err(message) => {
                        Some(EventData::Loaded { migration: None, missing_mods: Vec::new(), error: Some(message) })
                    }
                }
            }
            Request::Reload => match session.reload() {
                Ok(reset) => {
                    work.new_month();
                    // A failed step was undone, so a corrected model carries on from the
                    // end of the last good month.
                    *failed = None;
                    let _ = work.replies.send(Reply::Model(Box::new(model_info(session))));
                    Some(EventData::Reloaded { reset, error: None })
                }
                Err(e) => Some(EventData::Reloaded { reset: Vec::new(), error: Some(e.to_string()) }),
            },
            Request::Forecast(changes, months, tag) => work.forecast(session, &changes, months, tag),
            Request::Records(entity, where_row, count, columns, tag) => {
                let result = session.records(&entity, &where_row, count, &columns).map_err(|e| e.to_string());
                Some(EventData::Records { tag, result })
            }
            Request::Effects(levers, months) => work.effects(session, levers, months),
        }
    }
}

/// What the worker needs to start work on threads of its own.
struct Work {
    replies: Sender<Reply>,
    /// Stage S13.1: bumped whenever effects already computed go stale.
    generation: Arc<AtomicU64>,
    looks: Arc<Looks>,
    /// Stage S14.3: the effects table asked for since the last month, load or reload (its
    /// levers in order, and months); a lever change starts it again.
    table: Option<(Vec<String>, u64)>,
    /// Stage S14.3: a game was just loaded: send its saved effects table, if it has one.
    send_saved: bool,
}

impl Work {
    /// A month, a load or a reload: everything looked ahead at is stale.
    fn new_month(&mut self) {
        self.generation.fetch_add(1, Ordering::SeqCst);
        self.looks.month.fetch_add(1, Ordering::SeqCst);
        self.looks.state.fetch_add(1, Ordering::SeqCst);
        self.table = None;
    }

    /// Stage S14.3: a lever change alters the "as is" branch, so an effects table asked
    /// for this month starts again, with that lever first.
    fn lever_changed(&mut self, session: &Session, lever: &str) -> Option<EventData> {
        self.looks.state.fetch_add(1, Ordering::SeqCst);
        let Some((mut levers, months)) = self.table.take() else {
            // No table asked for this month: one already made (a saved one) is stale.
            self.generation.fetch_add(1, Ordering::SeqCst);
            return None;
        };
        if let Some(k) = levers.iter().position(|l| l == lever) {
            let first = levers.remove(k);
            levers.insert(0, first);
        }
        self.effects(session, levers, months)
    }

    /// Stage S13.1: a new table makes any earlier one stale. The worker only copies the
    /// game; the table is computed on threads of its own (stage S14.3: every core but one,
    /// pausing between months while a forecast runs), so the next month never waits for it.
    fn effects(&mut self, session: &Session, levers: Vec<String>, months: u64) -> Option<EventData> {
        let mine = self.generation.fetch_add(1, Ordering::SeqCst) + 1;
        self.table = Some((levers.clone(), months));
        let state = self.looks.state.load(Ordering::SeqCst);
        let fork = session.fork();
        if let Ok(mut table) = self.looks.table.lock() {
            *table = Some((mine, months, Vec::new(), false));
        }
        let (replies, generation, looks) =
            (self.replies.clone(), Arc::clone(&self.generation), Arc::clone(&self.looks));
        let spawned = std::thread::Builder::new().name("polisim-effects".to_string()).spawn(move || {
            let stale = || generation.load(Ordering::SeqCst) != mine;
            let stop = || {
                while looks.forecasting.load(Ordering::SeqCst) > 0 && !stale() {
                    std::thread::sleep(std::time::Duration::from_millis(2));
                }
                stale()
            };
            let sent = AtomicU64::new(0);
            let each = |effect: Effect| {
                if !stale() {
                    if let Ok(mut table) = looks.table.lock()
                        && let Some((g, _, found, _)) = table.as_mut()
                        && *g == mine
                    {
                        found.push(effect.clone());
                    }
                    sent.fetch_add(1, Ordering::SeqCst);
                    let event = EventData::Effect { generation: mine, effect: Box::new(effect) };
                    let _ = replies.send(Reply::Event(event));
                }
            };
            let finished = match fork {
                // A panic in the engine ends the table early, not the game.
                Ok(fork) => std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    let as_is = match looks.as_is(state, months) {
                        Some(outlook) => Ok(outlook),
                        None => match fork.run_until(&[], months, &stop) {
                            Ok(None) => return,
                            Ok(Some(outlook)) => {
                                looks.keep_as_is(state, months, &outlook);
                                Ok(outlook)
                            }
                            Err(e) => Err(e),
                        },
                    };
                    fork.effects_from(&as_is, &levers, months, effect_threads(), &stop, &each);
                }))
                .is_ok(),
                Err(e) => {
                    for lever in levers {
                        each(Effect { lever, step: 0.0, forecast: Err(e.clone()) });
                    }
                    true
                }
            };
            if !stale() {
                if let Ok(mut table) = looks.table.lock()
                    && let Some((g, _, _, complete)) = table.as_mut()
                    && *g == mine
                {
                    *complete = finished;
                }
                let count = sent.load(Ordering::SeqCst);
                let _ = replies.send(Reply::Event(EventData::EffectsDone { generation: mine, count }));
            }
        });
        spawned.err().map(|e| EventData::Failed(format!("cannot start the effects thread: {e}")))
    }

    /// Stage S14.3: a forecast on a thread of its own. The newest request wins: an older
    /// one, or one for a game since stepped, loaded or reloaded, stops at the next month
    /// and says nothing. It shares the "as is" branch with the effects table.
    fn forecast(
        &mut self,
        session: &Session,
        changes: &[(String, RawValue)],
        months: u64,
        tag: String,
    ) -> Option<EventData> {
        let looks = &self.looks;
        let mine = looks.forecast.fetch_add(1, Ordering::SeqCst) + 1;
        let (fork, changes) = match session.fork().and_then(|fork| session.checked(changes).map(|c| (fork, c))) {
            Ok(ready) => ready,
            Err(e) => return Some(EventData::Forecast { tag, months, result: Err(e.to_string()) }),
        };
        let (month, state) = (looks.month.load(Ordering::SeqCst), looks.state.load(Ordering::SeqCst));
        let running = Running::start(looks);
        let (replies, looks) = (self.replies.clone(), Arc::clone(looks));
        let spawned = std::thread::Builder::new().name("polisim-forecast".to_string()).spawn(move || {
            let _running = running;
            let stale = || looks.forecast.load(Ordering::SeqCst) != mine || looks.month.load(Ordering::SeqCst) != month;
            let ran = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let forecast = fork.forecast(looks.as_is(state, months), &changes, months, &stale);
                if let Ok(Some(f)) = &forecast {
                    looks.keep_as_is(state, months, &f.as_is);
                }
                forecast
            }));
            let result = match ran {
                Ok(Ok(Some(forecast))) => Ok(Box::new(forecast)),
                Ok(Ok(None)) => return,
                Ok(Err(e)) => Err(e.to_string()),
                Err(_) => Err("internal error in the engine while looking ahead".to_string()),
            };
            if !stale() {
                let _ = replies.send(Reply::Event(EventData::Forecast { tag, months, result }));
            }
        });
        spawned.err().map(|e| EventData::Failed(format!("cannot start the forecast thread: {e}")))
    }

    /// Stage S14.3: a save keeps the effects table when it is complete and of the game as
    /// it is now.
    fn keep_table(&self, session: &mut Session) {
        let now = self.generation.load(Ordering::SeqCst);
        let table = self.looks.table.lock().ok().and_then(|t| t.clone());
        let table = table.filter(|(g, _, _, complete)| *g == now && *complete);
        session.keep_effects(table.map(|(_, months, effects, _)| (months, effects)));
    }

    /// Stage S14.3: a loaded game's saved effects table, sent as if just computed.
    fn saved_table(&mut self, session: &Session) {
        let Some((months, effects)) = session.effects_kept() else { return };
        let mine = self.generation.fetch_add(1, Ordering::SeqCst) + 1;
        if let Ok(mut table) = self.looks.table.lock() {
            *table = Some((mine, *months, effects.clone(), true));
        }
        for effect in effects {
            let event = EventData::Effect { generation: mine, effect: Box::new(effect.clone()) };
            let _ = self.replies.send(Reply::Event(event));
        }
        let count = effects.len() as u64;
        let _ = self.replies.send(Reply::Event(EventData::EffectsDone { generation: mine, count }));
    }
}

// ---------------------------------------------------------------------------- conversions

fn val(v: Val) -> Variant {
    match v {
        Val::I(x) => x.to_variant(),
        Val::F(x) => x.to_variant(),
        Val::B(x) => x.to_variant(),
    }
}

fn num(n: Num) -> Variant {
    match n {
        Num::Int(x) => match i64::try_from(x) {
            Ok(x) => x.to_variant(),
            Err(_) => (x as f64).to_variant(),
        },
        Num::Real(x) => x.to_variant(),
    }
}

fn opt_num(n: Option<Num>) -> Variant {
    n.map(num).unwrap_or_default()
}

fn toml_to_variant(value: &RawValue) -> Variant {
    match value {
        RawValue::String(s) => s.to_variant(),
        RawValue::Integer(i) => i.to_variant(),
        RawValue::Float(f) => f.to_variant(),
        RawValue::Boolean(b) => b.to_variant(),
        RawValue::Array(items) => {
            let mut array = VarArray::new();
            for item in items {
                array.push(&toml_to_variant(item));
            }
            array.to_variant()
        }
        RawValue::Table(table) => {
            let mut dict = VarDictionary::new();
            for (k, v) in table {
                dict.set(k.as_str(), &toml_to_variant(v));
            }
            dict.to_variant()
        }
        RawValue::Datetime(d) => d.to_string().to_variant(),
    }
}

fn raw_from_variant(value: &Variant) -> Option<RawValue> {
    match value.get_type() {
        VariantType::INT => Some(RawValue::Integer(value.to::<i64>())),
        VariantType::FLOAT => Some(RawValue::Float(value.to::<f64>())),
        VariantType::BOOL => Some(RawValue::Boolean(value.to::<bool>())),
        VariantType::STRING | VariantType::STRING_NAME => {
            let text = value.to::<GString>().to_string().replace(['_', ','], "");
            let text = text.trim();
            match text {
                "true" => Some(RawValue::Boolean(true)),
                "false" => Some(RawValue::Boolean(false)),
                _ => text
                    .parse::<i64>()
                    .map(RawValue::Integer)
                    .ok()
                    .or_else(|| text.parse::<f64>().ok().filter(|f| f.is_finite()).map(RawValue::Float)),
            }
        }
        _ => None,
    }
}

fn kind_name(kind: Kind) -> &'static str {
    kind.name()
}

fn catalogue_dict(catalogue: &Catalogue) -> VarDictionary {
    let mut entries = VarArray::new();
    for e in &catalogue.entries {
        let mut d = VarDictionary::new();
        d.set("name", e.name.as_str());
        d.set("kind", kind_name(e.kind));
        d.set(
            "type",
            match e.ty {
                Ty::Int => "int",
                Ty::Real => "real",
                Ty::Bool => "bool",
            },
        );
        d.set("unit", e.unit.as_str());
        d.set("shown_unit", e.shown_unit.as_str());
        d.set("money", e.money);
        d.set("entity", e.entity.clone().unwrap_or_default().as_str());
        d.set("label", e.label.as_str());
        d.set("doc", e.doc.as_str());
        match e.range {
            Some((lo, hi)) => {
                d.set("min", lo);
                d.set("max", hi);
                d.set("has_range", true);
            }
            None => d.set("has_range", false),
        }
        d.set("phase", e.phase.clone().unwrap_or_default().as_str());
        d.set("row", e.row.clone().unwrap_or_default().as_str());
        d.set("from", e.from.clone().unwrap_or_default().as_str());
        d.set("to", e.to.clone().unwrap_or_default().as_str());
        d.set("instrument", e.instrument.clone().unwrap_or_default().as_str());
        d.set("financial", e.financial);
        d.set("player", e.player);
        d.set("group", e.group.as_str());
        d.set("leaning", e.leaning.as_str());
        d.set("situation", e.situation.as_str());
        d.set("dilemma", e.dilemma.as_str());
        d.set("lag", e.lag.as_str());
        d.set("dims", &strings(&e.dims));
        d.set("inputs", &strings(&e.inputs));
        d.set("lagged_inputs", &strings(&e.lagged_inputs));
        entries.push(&d.to_variant());
    }
    let mut sectors = VarArray::new();
    for s in &catalogue.sectors {
        let mut d = VarDictionary::new();
        d.set("name", s.name.as_str());
        d.set("label", s.label.as_str());
        d.set("inflows", &strings(&s.inflows));
        d.set("outflows", &strings(&s.outflows));
        d.set("accounts", &strings(&s.accounts));
        sectors.push(&d.to_variant());
    }
    let mut dims = VarArray::new();
    for x in &catalogue.dims {
        let mut d = VarDictionary::new();
        d.set("name", x.name.as_str());
        d.set("labels", &strings(&x.labels));
        dims.push(&d.to_variant());
    }
    // Stage S9.1: the questions put to the player, each with its answers in order.
    let mut dilemmas = VarArray::new();
    for x in &catalogue.dilemmas {
        let mut d = VarDictionary::new();
        d.set("name", x.name.as_str());
        d.set("label", x.label.as_str());
        d.set("doc", x.doc.as_str());
        d.set("again_after", x.again_after.unwrap_or(0));
        let mut options = VarArray::new();
        for o in &x.options {
            let mut option = VarDictionary::new();
            option.set("name", o.name.as_str());
            option.set("label", o.label.as_str());
            option.set("doc", o.doc.as_str());
            option.set("months", o.months.unwrap_or(0));
            options.push(&option.to_variant());
        }
        d.set("options", &options);
        dilemmas.push(&d.to_variant());
    }
    let mut out = VarDictionary::new();
    out.set("dilemmas", &dilemmas);
    out.set("id", catalogue.id.as_str());
    out.set("legislature", catalogue.legislature);
    out.set("capital", catalogue.capital.as_str());
    out.set("capital_spent", catalogue.capital_spent.as_str());
    out.set("dims", &dims);
    out.set("currency", catalogue.currency.as_str());
    out.set("minor", catalogue.minor);
    out.set("step_unit", catalogue.step_unit.as_str());
    out.set("instruments", &strings(&catalogue.instruments));
    out.set("entries", &entries);
    out.set("sectors", &sectors);
    out
}

fn strings(items: &[String]) -> PackedStringArray {
    let mut out = PackedStringArray::new();
    for item in items {
        out.push(item.as_str());
    }
    out
}

/// Stage S14.3: a route through the dependency graph, as {name, lagged} dictionaries.
fn links(route: &[Link]) -> VarArray {
    route
        .iter()
        .map(|l| {
            let mut d = VarDictionary::new();
            d.set("name", l.name.as_str());
            d.set("lagged", l.lagged);
            d.to_variant()
        })
        .collect()
}

fn explanation_dict(e: &Explanation) -> VarDictionary {
    let mut parts = VarArray::new();
    for p in &e.parts {
        let mut d = VarDictionary::new();
        d.set("label", p.label.as_str());
        d.set("symbol", p.symbol.clone().unwrap_or_default().as_str());
        d.set("lagged", p.lagged);
        d.set("effect", &opt_num(p.effect));
        d.set("now", &opt_num(p.now));
        d.set("before", &opt_num(p.before));
        parts.push(&d.to_variant());
    }
    let mut d = VarDictionary::new();
    d.set("name", e.name.as_str());
    d.set("kind", kind_name(e.kind));
    d.set("step", e.step as i64);
    d.set("entity", e.entity.clone().unwrap_or_default().as_str());
    d.set("now", &num(e.now));
    d.set("before", &num(e.before));
    d.set("change", &num(e.change));
    d.set("remainder", &num(e.remainder));
    d.set("exact", e.remainder.is_zero());
    d.set("note", e.note.clone().unwrap_or_default().as_str());
    d.set("parts", &parts);
    d
}

fn event_dict(event: EventData) -> VarDictionary {
    let mut d = VarDictionary::new();
    match event {
        EventData::Stepped { count } => {
            d.set("kind", "stepped");
            d.set("count", count as i64);
        }
        EventData::Failed(message) => {
            d.set("kind", "failed");
            d.set("error", message.as_str());
        }
        EventData::Explained { name, result } => {
            d.set("kind", "explained");
            d.set("name", name.as_str());
            match result {
                Ok(e) => d.set("explanation", &explanation_dict(&e)),
                Err(message) => d.set("error", message.as_str()),
            }
        }
        EventData::Saved { path, error } => {
            d.set("kind", "saved");
            d.set("path", path.as_str());
            d.set("error", error.unwrap_or_default().as_str());
        }
        EventData::Loaded { migration, missing_mods, error } => {
            d.set("kind", "loaded");
            d.set("error", error.unwrap_or_default().as_str());
            d.set("missing_mods", &strings(&missing_mods));
            // Stage S7.0: a save made with other model files, and what loading it did.
            d.set("migrated", migration.is_some());
            let m = migration.unwrap_or_default();
            d.set("carried", m.carried as i64);
            d.set("reset", &strings(&m.reset));
            d.set("clamped", &strings(&m.clamped));
            d.set("dropped", &strings(&m.dropped));
            let renamed: Vec<String> = m.renamed.iter().map(|(a, b)| format!("{a}\t{b}")).collect();
            d.set("renamed", &strings(&renamed));
        }
        EventData::Reloaded { reset, error } => {
            d.set("kind", "reloaded");
            d.set("reset", &strings(&reset));
            d.set("error", error.unwrap_or_default().as_str());
        }
        EventData::Forecast { tag, months, result } => {
            d.set("kind", "forecast");
            d.set("tag", tag.as_str());
            d.set("months", months as i64);
            look_ahead(&mut d, result.as_deref().map_err(String::as_str));
        }
        EventData::Effect { effect, .. } => {
            d.set("kind", "effects");
            d.set("lever", effect.lever.as_str());
            d.set("step", effect.step);
            let message = effect.forecast.as_ref().err().map(|e| e.to_string()).unwrap_or_default();
            look_ahead(&mut d, effect.forecast.as_ref().map_err(|_| message.as_str()));
        }
        EventData::EffectsDone { count, .. } => {
            d.set("kind", "effects_done");
            d.set("count", count as i64);
        }
        EventData::Records { tag, result } => {
            d.set("kind", "records");
            d.set("tag", tag.as_str());
            let mut records = VarArray::new();
            for r in result.as_deref().unwrap_or_default() {
                let mut x = VarDictionary::new();
                x.set("id", r.id as i64);
                x.set("weight", r.weight);
                for (name, value) in &r.values {
                    x.set(name.as_str(), &val(*value));
                }
                records.push(&x.to_variant());
            }
            d.set("records", &records);
            d.set("error", result.err().unwrap_or_default().as_str());
        }
    }
    // Stage S13.1: the S13 client reads `type`; earlier clients read `kind`.
    let kind = d.get("kind").unwrap_or_default();
    d.set("type", &kind);
    d
}

/// Stage S13.1: a forecast's `rows` (row name to `[as_is, changed]`), `cells` (name to
/// `{as_is, changed}`) and `error` ("" when it ran; otherwise the rest is empty).
fn look_ahead(d: &mut VarDictionary, result: Result<&Forecast, &str>) {
    let mut rows = VarDictionary::new();
    let mut cells = VarDictionary::new();
    if let Ok(f) = result {
        let (a, b): (&Outlook, &Outlook) = (&f.as_is, &f.changed);
        for ((name, x), (_, y)) in a.rows.iter().zip(&b.rows) {
            let pair: VarArray = [val(*x), val(*y)].into_iter().collect();
            rows.set(name.as_str(), &pair);
        }
        for ((name, x), (_, y)) in a.cells.iter().zip(&b.cells) {
            let mut pair = VarDictionary::new();
            pair.set("as_is", &PackedFloat64Array::from(x.as_slice()));
            pair.set("changed", &PackedFloat64Array::from(y.as_slice()));
            cells.set(name.as_str(), &pair);
        }
    }
    d.set("rows", &rows);
    d.set("cells", &cells);
    d.set("error", result.err().unwrap_or_default());
}

// ---------------------------------------------------------------------------- the class

/// One game. Create it with `PoliSim.new()`, then call `open()`.
#[derive(GodotClass)]
#[class(base = RefCounted)]
pub struct PoliSim {
    requests: Option<Sender<Request>>,
    replies: Option<Receiver<Reply>>,
    thread: Option<JoinHandle<()>>,
    outstanding: Arc<AtomicUsize>,
    /// Stage S13.1: bumped whenever effects already computed go stale.
    generation: Arc<AtomicU64>,
    /// Stage S14.3: what the forecast and effects threads share; a new one for each game.
    looks: Arc<Looks>,
    model: Option<Arc<Model>>,
    catalogue: Option<Catalogue>,
    play: VarDictionary,
    scenario_name: String,
    view: View,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for PoliSim {
    fn init(base: Base<RefCounted>) -> Self {
        PoliSim {
            requests: None,
            replies: None,
            thread: None,
            outstanding: Arc::new(AtomicUsize::new(0)),
            generation: Arc::new(AtomicU64::new(0)),
            looks: Arc::new(Looks::default()),
            model: None,
            catalogue: None,
            play: VarDictionary::new(),
            scenario_name: String::new(),
            view: View::default(),
            base,
        }
    }
}

impl Drop for PoliSim {
    fn drop(&mut self) {
        self.close();
    }
}

impl PoliSim {
    fn close(&mut self) {
        self.requests = None; // ends the worker's loop
        // Stage S14.3: forecasts and effects still running for this game stop.
        self.generation.fetch_add(1, Ordering::SeqCst);
        self.looks.month.fetch_add(1, Ordering::SeqCst);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
        self.replies = None;
    }

    fn send(&mut self, request: Request) -> bool {
        let Some(requests) = &self.requests else { return false };
        self.outstanding.fetch_add(1, Ordering::SeqCst);
        if requests.send(request).is_err() {
            self.outstanding.fetch_sub(1, Ordering::SeqCst);
            return false;
        }
        true
    }

    fn row_value(map: &BTreeMap<String, Val>, name: &str) -> Variant {
        map.get(name).copied().map(val).unwrap_or_default()
    }
}

#[godot_api]
impl PoliSim {
    /// Starts a new game from a scenario file. Returns an error message, or "" on success.
    #[func]
    fn open(&mut self, scenario_path: GString) -> GString {
        self.open_with_mods(scenario_path, PackedStringArray::new())
    }

    /// Stage S7.1: starts a game with mods the player chose (folders), after the scenario's
    /// own. Returns "" or the reason it could not start.
    #[func]
    fn open_with_mods(&mut self, scenario_path: GString, mods: PackedStringArray) -> GString {
        self.open_game(scenario_path, mods, GString::new())
    }

    /// Stage S7.4: as `open_with_mods`, with the game's words in `language` (a code from
    /// the model's `text/` folder; "" for the model's own).
    #[func]
    fn open_game(&mut self, scenario_path: GString, mods: PackedStringArray, language: GString) -> GString {
        self.close();
        let path = PathBuf::from(scenario_path.to_string());
        let mods: Vec<PathBuf> = mods.as_slice().iter().map(|m| PathBuf::from(m.to_string())).collect();
        let mut session = match Session::open_with_mods(&path, &mods) {
            Ok(s) => s,
            Err(e) => return e.to_string().as_str().into(),
        };
        if !language.is_empty()
            && let Err(e) = session.set_language(&language.to_string())
        {
            return e.to_string().as_str().into();
        }
        self.scenario_name = session.scenario().name.clone();
        let mut play = VarDictionary::new();
        for (k, v) in &session.scenario().play {
            play.set(k.as_str(), &toml_to_variant(v));
        }
        self.play = play;
        let info = model_info(&session);
        self.model = Some(info.model);
        self.catalogue = Some(info.catalogue);
        self.view = view_of(&session);
        self.looks = Arc::new(Looks::default());
        let looks = Arc::clone(&self.looks);
        let (request_tx, request_rx) = channel();
        let (reply_tx, reply_rx) = channel();
        let outstanding = Arc::clone(&self.outstanding);
        outstanding.store(0, Ordering::SeqCst);
        // A new game makes any table still being computed for the old one stale.
        self.generation.fetch_add(1, Ordering::SeqCst);
        let generation = Arc::clone(&self.generation);
        let spawned = std::thread::Builder::new()
            .name("polisim-simulation".to_string())
            .spawn(move || worker(session, request_rx, reply_tx, outstanding, generation, looks));
        match spawned {
            Ok(handle) => {
                self.thread = Some(handle);
                self.requests = Some(request_tx);
                self.replies = Some(reply_rx);
                GString::new()
            }
            Err(e) => format!("cannot start the simulation thread: {e}").as_str().into(),
        }
    }

    /// True while requests are still being worked on.
    #[func]
    fn is_busy(&self) -> bool {
        self.outstanding.load(Ordering::SeqCst) > 0
    }

    /// Applies finished work to the mirror and returns what happened, as a list of
    /// dictionaries with a "kind" key: stepped, failed, explained, saved, loaded, reloaded.
    #[func]
    fn poll(&mut self) -> VarArray {
        let mut events = VarArray::new();
        let Some(replies) = &self.replies else { return events };
        let mut out = Vec::new();
        // Stage S14.3: updates are applied in the order sent, so all state is in place
        // before any event is returned.
        while let Ok(reply) = replies.try_recv() {
            match reply {
                Reply::Update(u) => self.view.apply(*u),
                Reply::Model(info) => {
                    self.model = Some(info.model);
                    self.catalogue = Some(info.catalogue);
                }
                Reply::Event(e) => out.push(e),
            }
        }
        let now = self.generation.load(Ordering::SeqCst);
        for e in out {
            // Stage S13.1: effects of a game since stepped, loaded or reloaded are dropped.
            if let EventData::Effect { generation, .. } | EventData::EffectsDone { generation, .. } = &e
                && *generation != now
            {
                continue;
            }
            events.push(&event_dict(e).to_variant());
        }
        events
    }

    /// Runs `steps` steps on the worker thread. Results arrive through `poll()`.
    #[func]
    fn advance(&mut self, steps: i64) -> bool {
        self.send(Request::Step(steps.max(0) as u64))
    }

    /// Schedules a lever change for the next step. Money in major units. Returns an error
    /// message, or "" if the change was accepted.
    #[func]
    fn set_lever(&mut self, name: GString, value: Variant) -> GString {
        let Some(model) = &self.model else { return "no game is open".into() };
        let name = name.to_string();
        let Some(raw) = raw_from_variant(&value) else { return "not a number or true/false".into() };
        match check_lever(model, &name, &raw) {
            Ok(checked) => {
                self.view.pending.retain(|(l, _)| *l != name);
                self.view.pending.push((name.clone(), checked));
                self.send(Request::SetLever(name, raw));
                GString::new()
            }
            Err(e) => e.to_string().as_str().into(),
        }
    }

    /// Stage S12.4: what changing `name` to `value` next month would cost in political
    /// capital, as the engine will reckon it (-1 when it would be no bill: no capital, no
    /// leaning, no change, or a value the lever cannot take).
    #[func]
    fn bill_cost(&self, name: GString, value: Variant) -> f64 {
        let (Some(model), Some((bill, swing))) = (&self.model, self.view.capital_prices) else { return -1.0 };
        let name = name.to_string();
        let Some(raw) = raw_from_variant(&value) else { return -1.0 };
        let Some(d) = model.sym_index.get(&name).map(|&i| &model.symbols[i]) else { return -1.0 };
        let (Ok(new), Some(&old)) = (check_lever(model, &name, &raw), self.view.latest.get(&name)) else {
            return -1.0;
        };
        if d.spec.get("leaning").is_none() || new == old {
            return -1.0;
        }
        polisim_core::bill_cost(bill, swing, d, new, old)
    }

    /// Stage S13.1: what the legislature would do with a change of `lever` to `value` next
    /// month, after the changes already waiting, answered at once from the mirror: `bill`,
    /// `votes_for`, `seats`, `passes` (the vote would carry), `cost` (-1 without capital or
    /// when it is no bill) and `affordable` (the capital less the waiting bills' costs
    /// covers it). Empty when the lever or value is not valid.
    #[func]
    fn vote_preview(&self, lever: GString, value: Variant) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(model) = &self.model else { return d };
        let name = lever.to_string();
        let Some(raw) = raw_from_variant(&value) else { return d };
        let Ok(new) = check_lever(model, &name, &raw) else { return d };
        let decl = &model.symbols[model.sym_index[&name]];
        let spent = model.legislature.and_then(|l| l.capital).is_some_and(|c| model.symbols[c.spent].name == name);
        if spent || decl.spec.contains_key("dilemma") {
            return d;
        }
        let preview = match &self.view.chamber {
            Some(chamber) => {
                chamber.preview(model, &name, new, |l| self.view.latest.get(l).copied(), &self.view.pending)
            }
            None => polisim_core::VotePreview {
                bill: false,
                votes_for: 0,
                seats: 0,
                passes: true,
                cost: None,
                affordable: true,
            },
        };
        d.set("bill", preview.bill);
        d.set("votes_for", preview.votes_for);
        d.set("seats", preview.seats);
        d.set("passes", preview.passes);
        d.set("cost", preview.cost.unwrap_or(-1.0));
        d.set("affordable", preview.affordable);
        d
    }

    /// Stage S13.1: runs the game `months` ahead as it is and with `changes` (lever name to
    /// value, as typed) besides, applied directly; the answer arrives as a "forecast" event
    /// with this `tag`.
    #[func]
    fn request_forecast(&mut self, changes: VarDictionary, months: i64, tag: GString) -> bool {
        let changes = changes
            .iter_shared()
            .map(|(k, v)| (k.to_string(), raw_from_variant(&v).unwrap_or_else(|| RawValue::String(v.to_string()))))
            .collect();
        self.send(Request::Forecast(changes, months.max(0) as u64, tag.to_string()))
    }

    /// Stage S13.1: the effects table: one "effects" event per lever (each nudged one step,
    /// `months` ahead), computed off the worker, then "effects_done". A month, a load, a
    /// reload or a new table makes it stale: what is left of it is dropped.
    #[func]
    fn request_effects(&mut self, levers: PackedStringArray, months: i64) -> bool {
        self.request_effects_first(PackedStringArray::new(), levers, months)
    }

    /// Stage S14.3: as `request_effects`, doing the levers in `first` (those also in
    /// `levers`, in their order) before the rest; for the policy under the pointer.
    #[func]
    fn request_effects_first(&mut self, first: PackedStringArray, levers: PackedStringArray, months: i64) -> bool {
        let levers: Vec<String> = levers.as_slice().iter().map(|l| l.to_string()).collect();
        let mut order: Vec<String> =
            first.as_slice().iter().map(|l| l.to_string()).filter(|l| levers.contains(l)).collect();
        for lever in levers {
            if !order.contains(&lever) {
                order.push(lever);
            }
        }
        self.send(Request::Effects(order, months.max(0) as u64))
    }

    /// Stage S14.3: every value a change in `from` reaches through the model's formulas,
    /// nearest first, each as {name, lagged} (lagged: the route found passes a lag, so the
    /// change shows there a month or more later). Empty for an unknown name. Answered at
    /// once from the catalogue.
    #[func]
    fn reach(&self, from: GString) -> VarArray {
        let Some(catalogue) = &self.catalogue else { return VarArray::new() };
        links(&catalogue.reach(&from.to_string()))
    }

    /// Stage S14.3: a shortest chain of values from `from` to `to`, each reading the one
    /// before it, both ends included, each as {name, lagged} (lagged: the link into it is
    /// through a lag). Empty when `to` cannot be reached.
    #[func]
    fn path(&self, from: GString, to: GString) -> VarArray {
        let Some(catalogue) = &self.catalogue else { return VarArray::new() };
        links(&catalogue.path(&from.to_string(), &to.to_string()))
    }

    /// Stage S13.1: up to `count` records of `entity` for which `where_row` is true ("" for
    /// all), each with id, weight and the latest value of each of `columns`, as a "records"
    /// event with this `tag`.
    #[func]
    fn request_records(
        &mut self,
        entity: GString,
        where_row: GString,
        count: i64,
        columns: PackedStringArray,
        tag: GString,
    ) -> bool {
        let columns = columns.as_slice().iter().map(|c| c.to_string()).collect();
        let count = usize::try_from(count.max(0)).unwrap_or(usize::MAX);
        self.send(Request::Records(entity.to_string(), where_row.to_string(), count, columns, tag.to_string()))
    }

    #[func]
    fn cancel_lever(&mut self, name: GString) {
        let name = name.to_string();
        self.view.pending.retain(|(l, _)| *l != name);
        self.send(Request::CancelLever(name));
    }

    /// Asks why `name` changed in the last step; the answer arrives as an "explained" event.
    #[func]
    fn request_explanation(&mut self, name: GString) -> bool {
        self.send(Request::Explain(name.to_string()))
    }

    #[func]
    fn save_game(&mut self, path: GString) -> bool {
        self.send(Request::Save(PathBuf::from(path.to_string())))
    }

    #[func]
    fn load_game(&mut self, path: GString) -> bool {
        self.send(Request::Load(PathBuf::from(path.to_string())))
    }

    /// Reads the model files again and continues on the changed model.
    #[func]
    fn reload_model(&mut self) -> bool {
        self.send(Request::Reload)
    }

    // ---------------------------------------------------------------- reading

    #[func]
    fn engine_version(&self) -> GString {
        polisim_core::VERSION.into()
    }

    /// Stage S7.1: the scenarios a player can start under `base`
    /// (`base/models/*/scenarios/*.toml` with a `[play] title`), each as path, title,
    /// country, start and the id of its model, ordered by path.
    #[func]
    fn scenarios(&self, base: GString) -> VarArray {
        let mut found = Vec::new();
        let models = PathBuf::from(base.to_string()).join("models");
        for model in std::fs::read_dir(&models).into_iter().flatten().flatten() {
            for file in std::fs::read_dir(model.path().join("scenarios")).into_iter().flatten().flatten() {
                let path = file.path();
                if path.extension().is_some_and(|e| e == "toml")
                    && let Some(entry) = scenario_entry(&path)
                {
                    found.push((path, entry));
                }
            }
        }
        found.sort_by(|a, b| a.0.cmp(&b.0));
        found.into_iter().map(|(_, entry)| entry.to_variant()).collect()
    }

    /// Stage S7.1: the mods in these folders (each mod a folder with `mod.toml`), as path,
    /// id, name, version, description and model; a mod whose `mod.toml` cannot be read is
    /// listed with its error.
    #[func]
    fn mods(&self, folders: PackedStringArray) -> VarArray {
        let mut found = Vec::new();
        for folder in folders.as_slice() {
            for dir in std::fs::read_dir(folder.to_string()).into_iter().flatten().flatten() {
                let dir = dir.path();
                if !dir.join("mod.toml").is_file() {
                    continue;
                }
                let mut d = VarDictionary::new();
                d.set("path", dir.to_string_lossy().as_ref());
                match polisim_core::read_mod(&dir) {
                    Ok((info, _, _)) => {
                        d.set("id", info.id.as_str());
                        d.set("name", info.name.as_str());
                        d.set("version", info.version.as_str());
                        d.set("description", info.description.as_str());
                        d.set("model", info.model.as_deref().unwrap_or(""));
                        d.set("error", "");
                    }
                    Err(e) => {
                        let name = dir.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
                        d.set("id", name.as_str());
                        d.set("name", name.as_str());
                        d.set("error", e.to_string().as_str());
                    }
                }
                found.push((dir, d));
            }
        }
        found.sort_by(|a, b| a.0.cmp(&b.0));
        found.into_iter().map(|(_, d)| d.to_variant()).collect()
    }

    /// Stage S7.1: the mods this game runs with, in order, as id, name, version and the
    /// notes their loading made.
    #[func]
    fn active_mods(&self) -> VarArray {
        let Some(model) = &self.model else { return VarArray::new() };
        model
            .mods
            .iter()
            .map(|m| {
                let mut d = VarDictionary::new();
                d.set("id", m.id.as_str());
                d.set("name", m.name.as_str());
                d.set("version", m.version.as_str());
                d.to_variant()
            })
            .collect()
    }

    /// Stage S7.1: what loading the mods is worth telling the player.
    #[func]
    fn mod_notes(&self) -> PackedStringArray {
        let Some(model) = &self.model else { return PackedStringArray::new() };
        strings(&model.mod_notes)
    }

    #[func]
    fn scenario_name(&self) -> GString {
        self.scenario_name.as_str().into()
    }

    /// The scenario's `[play]` table: country name, start date, government sector, etc.
    #[func]
    fn play_settings(&self) -> VarDictionary {
        self.play.clone()
    }

    /// Everything the interface needs to know about the model: see `describe.rs`.
    #[func]
    fn catalogue(&self) -> VarDictionary {
        self.catalogue.as_ref().map(catalogue_dict).unwrap_or_default()
    }

    #[func]
    fn steps_done(&self) -> i64 {
        self.view.steps_done as i64
    }

    /// The error that stopped the run, or "".
    #[func]
    fn failure(&self) -> GString {
        self.view.failed.clone().unwrap_or_default().as_str().into()
    }

    /// A result of the last step by row name, or a lever's setting; null if unknown.
    #[func]
    fn latest(&self, row: GString) -> Variant {
        Self::row_value(&self.view.latest, &row.to_string())
    }

    /// The same result one step earlier.
    #[func]
    fn previous(&self, row: GString) -> Variant {
        Self::row_value(&self.view.previous, &row.to_string())
    }

    /// Format 1: a one-dimensional value's cells after the last step, with the cells one
    /// step earlier (empty before the second step), the dimension's name and its members'
    /// labels. Empty if the value is unknown, has other than one dimension or more than 64
    /// cells, or no step has run.
    #[func]
    fn cells(&self, name: GString) -> VarDictionary {
        let mut d = VarDictionary::new();
        let name = name.to_string();
        let Some((now, before)) = self.view.cells.get(&name) else { return d };
        let catalogue = self.catalogue.as_ref();
        let dim = catalogue.and_then(|c| c.entries.iter().find(|e| e.name == name)).map(|e| e.dims[0].clone());
        let labels = dim.as_ref().and_then(|n| catalogue.and_then(|c| c.dims.iter().find(|x| &x.name == n)));
        d.set("values", &PackedFloat64Array::from(now.as_slice()));
        d.set("previous", &PackedFloat64Array::from(before.as_slice()));
        d.set("dim", dim.unwrap_or_default().as_str());
        d.set("labels", &strings(labels.map(|x| x.labels.as_slice()).unwrap_or_default()));
        d
    }

    /// Lever changes waiting for the next step: lever name to stored value.
    #[func]
    fn pending(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        for (name, v) in &self.view.pending {
            d.set(name.as_str(), &val(*v));
        }
        d
    }

    /// Lever changes made: dictionaries with step, lever, value, and the vote (passed, and
    /// votes_for and seats, both 0 when there was no vote). A change with passed false was
    /// voted down and did not take effect.
    #[func]
    fn changes(&self) -> VarArray {
        let mut out = VarArray::new();
        for c in &self.view.changes {
            let mut d = VarDictionary::new();
            d.set("step", c.step as i64);
            d.set("lever", c.lever.as_str());
            d.set("value", &val(c.value));
            d.set("passed", c.passed);
            d.set("votes_for", c.votes_for);
            d.set("seats", c.seats);
            d.set("cost", c.cost.unwrap_or(-1.0));
            d.set("refused", c.refused);
            out.push(&d.to_variant());
        }
        out
    }

    /// One result over every completed step (NaN where it did not exist).
    #[func]
    fn series(&self, row: GString) -> PackedFloat64Array {
        let mut out = PackedFloat64Array::new();
        if let Some(values) = self.view.history.series(&row.to_string()) {
            for v in values {
                out.push(*v);
            }
        }
        out
    }

    /// Indices of the completed steps, parallel to `series()`.
    #[func]
    fn history_steps(&self) -> PackedInt64Array {
        let mut out = PackedInt64Array::new();
        for s in &self.view.history.steps {
            out.push(*s as i64);
        }
        out
    }

    /// The state hash after each completed step, as hexadecimal text.
    #[func]
    fn hashes(&self) -> PackedStringArray {
        let mut out = PackedStringArray::new();
        for h in &self.view.history.hashes {
            out.push(pyfmt::hex(h).as_str());
        }
        out
    }
}
