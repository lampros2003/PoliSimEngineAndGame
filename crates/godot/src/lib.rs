//! The bridge between the PoliSim engine and the Godot game client.
//!
//! GDScript sees one class, `PoliSim`. The game session runs on a worker thread owned by
//! this library; the interface thread sends it requests and reads a mirror of the
//! session's state that the worker refreshes after every request. No Godot object is
//! ever touched off the main thread, and a slow step never blocks the window.
//!
//! Units: values read back are as the engine stores them (money in minor units, such as
//! pence). Lever settings are written as a person types them (money in major units).

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc::{Receiver, Sender, channel};
use std::thread::JoinHandle;

use godot::prelude::*;
use polisim_core::describe::Catalogue;
use polisim_core::model::Kind;
use polisim_core::session::{Change, History};
use polisim_core::{Explanation, Model, Num, RawValue, Session, Ty, Val, check_lever, pyfmt};

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
}

/// Sent when the model changes: on opening, loading and reloading.
struct ModelInfo {
    model: Arc<Model>,
    catalogue: Catalogue,
}

enum Reply {
    View(Box<View>),
    Model(Box<ModelInfo>),
    Event(EventData),
}

enum EventData {
    Stepped { count: u64 },
    Failed(String),
    Explained { name: String, result: Result<Box<Explanation>, String> },
    Saved { path: String, error: Option<String> },
    Loaded { error: Option<String> },
    Reloaded { reset: Vec<String>, error: Option<String> },
}

fn view_of(session: &Session, failed: &Option<String>) -> View {
    let catalogue = session.catalogue();
    let mut latest = BTreeMap::new();
    let mut previous = BTreeMap::new();
    for entry in &catalogue.entries {
        let Some(row) = &entry.row else { continue };
        if let Some(v) = session.latest(row) {
            latest.insert(row.clone(), v);
        }
        if let Some(v) = session.previous(row) {
            previous.insert(row.clone(), v);
        }
    }
    View {
        steps_done: session.steps_done(),
        latest,
        previous,
        pending: session.pending(),
        changes: session.changes().to_vec(),
        history: session.history().clone(),
        failed: failed.clone(),
    }
}

fn model_info(session: &Session) -> ModelInfo {
    ModelInfo { model: Arc::new(session.model().clone()), catalogue: session.catalogue().clone() }
}

fn worker(mut session: Session, requests: Receiver<Request>, replies: Sender<Reply>, outstanding: Arc<AtomicUsize>) {
    let mut failed: Option<String> = None;
    for request in requests {
        let event = match request {
            Request::Step(count) => {
                let mut done = 0;
                let mut error = None;
                if let Some(message) = &failed {
                    error = Some(message.clone());
                } else {
                    for _ in 0..count {
                        match session.step() {
                            Ok(()) => done += 1,
                            Err(e) => {
                                error = Some(e.to_string());
                                failed = error.clone();
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
                None
            }
            Request::CancelLever(name) => {
                session.cancel_lever(&name);
                None
            }
            Request::Explain(name) => {
                let result = session.explain(&name).map(Box::new).map_err(|e| e.to_string());
                Some(EventData::Explained { name, result })
            }
            Request::Save(path) => {
                let error = std::fs::write(&path, session.save()).err().map(|e| e.to_string());
                Some(EventData::Saved { path: path.display().to_string(), error })
            }
            Request::Load(path) => {
                let loaded = std::fs::read(&path)
                    .map_err(|e| format!("cannot read {}: {e}", path.display()))
                    .and_then(|bytes| Session::load(session.scenario_path(), &bytes).map_err(|e| e.to_string()));
                match loaded {
                    Ok(next) => {
                        session = next;
                        failed = None;
                        let _ = replies.send(Reply::Model(Box::new(model_info(&session))));
                        Some(EventData::Loaded { error: None })
                    }
                    Err(message) => Some(EventData::Loaded { error: Some(message) }),
                }
            }
            Request::Reload => match session.reload() {
                Ok(reset) => {
                    let _ = replies.send(Reply::Model(Box::new(model_info(&session))));
                    Some(EventData::Reloaded { reset, error: None })
                }
                Err(e) => Some(EventData::Reloaded { reset: Vec::new(), error: Some(e.to_string()) }),
            },
        };
        let _ = replies.send(Reply::View(Box::new(view_of(&session, &failed))));
        if let Some(event) = event {
            let _ = replies.send(Reply::Event(event));
        }
        outstanding.fetch_sub(1, Ordering::SeqCst);
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
    let mut out = VarDictionary::new();
    out.set("id", catalogue.id.as_str());
    out.set("currency", catalogue.currency.as_str());
    out.set("minor", catalogue.minor);
    out.set("step_unit", catalogue.step_unit.as_str());
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
        EventData::Loaded { error } => {
            d.set("kind", "loaded");
            d.set("error", error.unwrap_or_default().as_str());
        }
        EventData::Reloaded { reset, error } => {
            d.set("kind", "reloaded");
            d.set("reset", &strings(&reset));
            d.set("error", error.unwrap_or_default().as_str());
        }
    }
    d
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
        self.close();
        let path = PathBuf::from(scenario_path.to_string());
        let session = match Session::open(&path) {
            Ok(s) => s,
            Err(e) => return e.to_string().as_str().into(),
        };
        self.scenario_name = session.scenario().name.clone();
        let mut play = VarDictionary::new();
        for (k, v) in &session.scenario().play {
            play.set(k.as_str(), &toml_to_variant(v));
        }
        self.play = play;
        let info = model_info(&session);
        self.model = Some(info.model);
        self.catalogue = Some(info.catalogue);
        self.view = view_of(&session, &None);
        let (request_tx, request_rx) = channel();
        let (reply_tx, reply_rx) = channel();
        let outstanding = Arc::clone(&self.outstanding);
        outstanding.store(0, Ordering::SeqCst);
        let spawned = std::thread::Builder::new()
            .name("polisim-simulation".to_string())
            .spawn(move || worker(session, request_rx, reply_tx, outstanding));
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
        let mut pending_model = None;
        let mut view = None;
        let mut out = Vec::new();
        while let Ok(reply) = replies.try_recv() {
            match reply {
                Reply::View(v) => view = Some(*v),
                Reply::Model(info) => pending_model = Some(*info),
                Reply::Event(e) => {
                    // Apply state before announcing the event that refers to it.
                    if let Some(v) = view.take() {
                        self.view = v;
                    }
                    if let Some(info) = pending_model.take() {
                        self.model = Some(info.model);
                        self.catalogue = Some(info.catalogue);
                    }
                    out.push(e);
                }
            }
        }
        if let Some(v) = view {
            self.view = v;
        }
        if let Some(info) = pending_model {
            self.model = Some(info.model);
            self.catalogue = Some(info.catalogue);
        }
        for e in out {
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

    /// Lever changes waiting for the next step: lever name to stored value.
    #[func]
    fn pending(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        for (name, v) in &self.view.pending {
            d.set(name.as_str(), &val(*v));
        }
        d
    }

    /// Lever changes that have taken effect: dictionaries with step, lever and value.
    #[func]
    fn changes(&self) -> VarArray {
        let mut out = VarArray::new();
        for c in &self.view.changes {
            let mut d = VarDictionary::new();
            d.set("step", c.step as i64);
            d.set("lever", c.lever.as_str());
            d.set("value", &val(c.value));
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
