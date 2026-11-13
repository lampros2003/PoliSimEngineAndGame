//! Model-file format 0: loading and structural validation.
//!
//! A port of oracle/polisim_oracle/model.py. Formulas are compiled later, by the
//! simulation.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};
use toml::{Table as Toml, Value};

use crate::error::{Error, Result, model_err};
use crate::program::{Ty, Val};
use crate::pyfmt;
use crate::rng::fnv1a32;
use crate::units::{self, Unit};

/// Function names of the formula language. With the five keywords they are reserved.
pub const FUNCTIONS: [&str; 17] = [
    "abs", "ceil", "clamp", "floor", "marginal", "max", "min", "muldiv", "per_step", "prev", "rand", "round",
    "safe_div", "select", "times_step", "wcount", "wsum",
];
const KEYWORDS: [&str; 5] = ["and", "or", "not", "true", "false"];
const SECTIONS: [&str; 12] =
    ["model", "sector", "instrument", "entity", "stream", "table", "param", "lever", "var", "state", "flow", "account"];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Param,
    Lever,
    Column,
    Var,
    Flow,
    State,
    Account,
}

impl Kind {
    pub fn name(self) -> &'static str {
        match self {
            Kind::Param => "param",
            Kind::Lever => "lever",
            Kind::Column => "column",
            Kind::Var => "var",
            Kind::Flow => "flow",
            Kind::State => "state",
            Kind::Account => "account",
        }
    }
}

/// Anything a formula can name.
#[derive(Clone, Debug)]
pub struct Decl {
    pub name: String,
    pub kind: Kind,
    pub ty: Ty,
    pub unit: Unit,
    /// File values are in major currency units and scaled on load.
    pub money: bool,
    /// `None`: one value for the nation. Otherwise one value per record of this entity.
    pub entity: Option<usize>,
    /// var and flow: evaluation phase. state: phase of its update.
    pub phase: Option<usize>,
    /// var and flow formula, or a state's `next` formula.
    pub expr: Option<String>,
    /// Raw initial value, or `{ column = "..." }`.
    pub initial: Option<Value>,
    pub range: Option<(f64, f64)>,
    pub spec: Toml,
}

#[derive(Clone, Debug)]
pub struct Entity {
    pub name: String,
    pub ids: Vec<u64>,
    pub weights: Vec<i64>,
    header: Vec<String>,
    /// Every CSV column as text, in header order.
    raw: Vec<Vec<String>>,
}

impl Entity {
    pub fn len(&self) -> usize {
        self.ids.len()
    }

    pub fn is_empty(&self) -> bool {
        self.ids.is_empty()
    }

    pub fn column(&self, name: &str) -> Option<&[String]> {
        // The last of two columns with one name wins, as in the oracle's dictionary.
        self.header.iter().rposition(|h| h == name).map(|i| self.raw[i].as_slice())
    }
}

#[derive(Clone, Debug)]
pub struct Table {
    pub name: String,
    pub unit: Unit,
    /// (lower threshold formula, rate formula), ascending.
    pub bands: Vec<(String, String)>,
}

#[derive(Clone, Debug)]
pub struct Sector {
    pub name: String,
    /// Entity that holds this sector's accounts record by record, if any.
    pub entity: Option<usize>,
}

#[derive(Clone, Debug)]
pub struct Instrument {
    pub name: String,
    pub unit: Unit,
    pub issuer: usize,
    /// Symbol index of the issuer's account.
    pub issuer_account: usize,
}

#[derive(Clone, Debug)]
pub struct Account {
    pub sym: usize,
    pub sector: usize,
    pub instrument: usize,
}

#[derive(Clone, Debug)]
pub struct Flow {
    pub sym: usize,
    /// Symbol indices of the paying and receiving accounts.
    pub src_account: usize,
    pub dst_account: usize,
}

#[derive(Clone, Debug)]
pub struct Model {
    pub root: PathBuf,
    pub id: String,
    pub currency: String,
    /// Minor units per major unit (100 pence per pound).
    pub minor: i64,
    pub step_unit: Unit,
    pub phases: Vec<String>,
    pub sectors: Vec<Sector>,
    pub instruments: Vec<Instrument>,
    pub entities: Vec<Entity>,
    pub streams: Vec<(String, u32)>,
    pub tables: Vec<Table>,
    /// In declaration order: columns, params, levers, vars, states, accounts, flows.
    pub symbols: Vec<Decl>,
    pub accounts: Vec<Account>,
    pub flows: Vec<Flow>,
    pub model_hash: [u8; 32],
    // Name lookups. These maps are never iterated, so their order cannot leak into a run.
    pub sym_index: HashMap<String, usize>,
    pub table_index: HashMap<String, usize>,
    pub entity_index: HashMap<String, usize>,
}

impl Model {
    pub fn stream_id(&self, name: &str) -> Option<u32> {
        self.streams.iter().find(|(n, _)| n == name).map(|(_, id)| *id)
    }

    pub fn sym(&self, name: &str) -> Option<&Decl> {
        self.sym_index.get(name).map(|i| &self.symbols[*i])
    }

    pub fn model_hash_hex(&self) -> String {
        pyfmt::hex(&self.model_hash)
    }
}

/// A raw value from a TOML file or a CSV cell.
#[derive(Clone, Copy)]
pub enum Raw<'a> {
    Toml(&'a Value),
    Text(&'a str),
}

enum Number {
    Whole(i64),
    Real(f64),
}

fn is_whole(text: &str) -> bool {
    let digits = text.strip_prefix(['+', '-']).unwrap_or(text);
    !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit())
}

fn show(raw: Raw) -> String {
    match raw {
        Raw::Text(t) => format!("{t:?}"),
        Raw::Toml(Value::String(s)) => format!("{s:?}"),
        Raw::Toml(v) => v.to_string_lossy(),
    }
}

trait Lossy {
    fn to_string_lossy(&self) -> String;
}

impl Lossy for Value {
    fn to_string_lossy(&self) -> String {
        match self {
            Value::Integer(i) => i.to_string(),
            Value::Float(f) => pyfmt::float_repr(*f),
            Value::Boolean(b) => b.to_string(),
            Value::String(s) => s.clone(),
            Value::Array(_) => "a list".to_string(),
            Value::Table(_) => "a table".to_string(),
            Value::Datetime(d) => d.to_string(),
        }
    }
}

/// Turns a TOML or CSV value into a run-time value of the declared type.
pub fn convert(raw: Raw, ty: Ty, money: bool, minor: i64, what: &str) -> Result<Val> {
    let text = match raw {
        Raw::Text(t) => Some(t),
        Raw::Toml(Value::String(s)) => Some(s.as_str()),
        Raw::Toml(_) => None,
    };
    if ty == Ty::Bool {
        if let Raw::Toml(Value::Boolean(b)) = raw {
            return Ok(Val::B(*b));
        }
        return match text.map(|t| t.trim().to_lowercase()).as_deref() {
            Some("1" | "true") => Ok(Val::B(true)),
            Some("0" | "false") => Ok(Val::B(false)),
            _ => model_err(format!("{what}: expected true or false, got {}", show(raw))),
        };
    }
    let number = match (raw, text) {
        (_, Some(text)) => {
            let text = text.trim();
            if is_whole(text) {
                match text.parse::<i64>() {
                    Ok(v) => Number::Whole(v),
                    // Too large for 64 bits: still a valid real, never a valid whole number.
                    Err(_) if ty == Ty::Real => Number::Real(text.parse::<f64>().unwrap_or(f64::NAN)),
                    Err(_) => return model_err(format!("{what}: {text:?} does not fit in 64 bits")),
                }
            } else {
                match text.parse::<f64>() {
                    Ok(v) => Number::Real(v),
                    Err(_) => return model_err(format!("{what}: {text:?} is not a number")),
                }
            }
        }
        (Raw::Toml(Value::Integer(i)), _) => Number::Whole(*i),
        (Raw::Toml(Value::Float(f)), _) => Number::Real(*f),
        _ => return model_err(format!("{what}: expected a number, got {}", show(raw))),
    };
    if ty == Ty::Real {
        return Ok(Val::F(match number {
            Number::Whole(i) => i as f64,
            Number::Real(f) => f,
        }));
    }
    let value = match (number, money) {
        (Number::Whole(i), true) => match i.checked_mul(minor) {
            Some(v) => v,
            None => return model_err(format!("{what}: {} does not fit in 64 bits", show(raw))),
        },
        (Number::Real(f), true) => {
            let scaled = f * minor as f64;
            if scaled.is_nan() || scaled.abs() > 9.0e18 {
                return model_err(format!("{what}: {} is out of range", show(raw)));
            }
            let rounded = scaled.round_ties_even();
            if (scaled - rounded).abs() > 1e-6 {
                return model_err(format!("{what}: {} has more decimal places than the currency", show(raw)));
            }
            rounded as i64
        }
        (Number::Whole(i), false) => i,
        (Number::Real(_), false) => return model_err(format!("{what}: expected a whole number, got {}", show(raw))),
    };
    Ok(Val::I(value))
}

fn unit_of(spec: &Toml, what: &str, default: Option<&str>) -> Result<Unit> {
    let text = match spec.get("unit") {
        Some(Value::String(s)) => s.as_str(),
        Some(_) => return model_err(format!("{what}: 'unit' must be text")),
        None => match default {
            Some(d) => d,
            None => return model_err(format!("{what}: missing 'unit'")),
        },
    };
    Unit::parse(text).map_err(|e| Error::Model(format!("{what}: {e}")))
}

fn type_of(spec: &Toml, what: &str) -> Result<(Ty, bool)> {
    match spec.get("type").and_then(Value::as_str) {
        Some("money") => Ok((Ty::Int, true)),
        Some("int") => Ok((Ty::Int, false)),
        Some("real") => Ok((Ty::Real, false)),
        Some("bool") => Ok((Ty::Bool, false)),
        _ => model_err(format!("{what}: 'type' must be one of money, int, real, bool")),
    }
}

fn range_of(spec: &Toml, money: bool, minor: i64, what: &str) -> Result<Option<(f64, f64)>> {
    let Some(value) = spec.get("range") else { return Ok(None) };
    let bound = |v: &Value| match v {
        Value::Integer(i) => Some(*i as f64),
        Value::Float(f) => Some(*f),
        _ => None,
    };
    let bounds = match value {
        Value::Array(items) if items.len() == 2 => bound(&items[0]).zip(bound(&items[1])),
        _ => None,
    };
    let Some((lo, hi)) = bounds else { return model_err(format!("{what}: 'range' must be [low, high]")) };
    let scale = if money { minor as f64 } else { 1.0 };
    Ok(Some((lo * scale, hi * scale)))
}

fn text_of<'a>(spec: &'a Toml, key: &str) -> Option<&'a str> {
    spec.get(key).and_then(Value::as_str)
}

fn table_of<'a>(value: &'a Value, what: &str) -> Result<&'a Toml> {
    match value {
        Value::Table(t) => Ok(t),
        _ => model_err(format!("{what}: expected a table")),
    }
}

/// A small RFC 4180 reader: commas, optional double quotes, LF or CRLF. Blank lines are skipped.
fn parse_csv(text: &str) -> Vec<Vec<String>> {
    let mut rows = Vec::new();
    let mut row: Vec<String> = Vec::new();
    let mut field = String::new();
    let mut quoted = false;
    let mut chars = text.chars().peekable();
    let end_row = |row: &mut Vec<String>, field: &mut String, rows: &mut Vec<Vec<String>>| {
        row.push(std::mem::take(field));
        if !(row.len() == 1 && row[0].is_empty()) {
            rows.push(std::mem::take(row));
        }
        row.clear();
    };
    while let Some(c) = chars.next() {
        if quoted {
            if c == '"' {
                if chars.peek() == Some(&'"') {
                    chars.next();
                    field.push('"');
                } else {
                    quoted = false;
                }
            } else {
                field.push(c);
            }
        } else if c == '"' && field.is_empty() {
            quoted = true;
        } else if c == ',' {
            row.push(std::mem::take(&mut field));
        } else if c == '\n' {
            end_row(&mut row, &mut field, &mut rows);
        } else if c == '\r' && chars.peek() == Some(&'\n') {
            // handled by the line feed that follows
        } else {
            field.push(c);
        }
    }
    if !field.is_empty() || !row.is_empty() {
        end_row(&mut row, &mut field, &mut rows);
    }
    rows
}

fn read_entity(root: &Path, name: &str, spec: &Toml) -> Result<(Entity, Vec<u8>, String)> {
    let what = format!("entity {name}");
    let (Some(data), Some(id), Some(weight)) = (text_of(spec, "data"), text_of(spec, "id"), text_of(spec, "weight")) else {
        return model_err(format!("{what}: needs 'data', 'id' and 'weight'"));
    };
    let path = root.join(data);
    let bytes = std::fs::read(&path).map_err(|e| Error::Model(format!("{what}: cannot read {}: {e}", path.display())))?;
    let text = std::str::from_utf8(&bytes).map_err(|_| Error::Model(format!("{what}: {data} is not UTF-8")))?;
    let mut rows = parse_csv(text);
    if rows.len() < 2 {
        return model_err(format!("{what}: {} has no rows", path.display()));
    }
    let header = rows.remove(0);
    let mut raw: Vec<Vec<String>> = vec![Vec::with_capacity(rows.len()); header.len()];
    for (line, row) in rows.into_iter().enumerate() {
        if row.len() != header.len() {
            return model_err(format!("{what}: row {} of {data} has {} fields, expected {}", line + 2, row.len(), header.len()));
        }
        for (column, cell) in raw.iter_mut().zip(row) {
            column.push(cell);
        }
    }
    let mut entity = Entity { name: name.to_string(), ids: Vec::new(), weights: Vec::new(), header, raw };
    for needed in [id, weight] {
        if entity.column(needed).is_none() {
            return model_err(format!("{what}: column {needed:?} not found in {data}"));
        }
    }
    let whole = |column: &str, label: &str| -> Result<Vec<i64>> {
        entity.column(column).unwrap().iter().map(|cell| match convert(Raw::Text(cell), Ty::Int, false, 1, label)? {
            Val::I(v) => Ok(v),
            _ => unreachable!("whole-number conversion"),
        }).collect()
    };
    let ids = whole(id, &format!("{what} id"))?;
    let weights = whole(weight, &format!("{what} weight"))?;
    let mut sorted = ids.clone();
    sorted.sort_unstable();
    if sorted.windows(2).any(|w| w[0] == w[1]) || sorted[0] < 0 {
        return model_err(format!("{what}: ids must be unique and non-negative"));
    }
    if weights.iter().any(|w| *w <= 0) {
        return model_err(format!("{what}: weights must be positive whole numbers"));
    }
    entity.ids = ids.into_iter().map(|v| v as u64).collect();
    entity.weights = weights;
    Ok((entity, bytes, relative_name(data)))
}

/// A relative path as the oracle hashes it: forward slashes, no `.` components.
fn relative_name(path: &str) -> String {
    path.split(['/', '\\']).filter(|part| !part.is_empty() && *part != ".").collect::<Vec<_>>().join("/")
}

struct Loader {
    minor: i64,
    phases: Vec<String>,
    symbols: Vec<Decl>,
    sym_index: HashMap<String, usize>,
    taken: Vec<String>, // table, stream and entity names
    entity_index: HashMap<String, usize>,
}

impl Loader {
    fn declare(&mut self, decl: Decl) -> Result<usize> {
        let name = decl.name.as_str();
        let mut chars = name.chars();
        let well_formed = chars.next().is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
            && chars.all(|c| c.is_ascii_alphanumeric() || c == '_');
        if !well_formed || FUNCTIONS.contains(&name) || KEYWORDS.contains(&name) {
            return model_err(format!("{} {name:?}: not a usable name", decl.kind.name()));
        }
        if self.sym_index.contains_key(name) || self.taken.iter().any(|t| t == name) {
            return model_err(format!("the name {name:?} is used twice"));
        }
        self.sym_index.insert(decl.name.clone(), self.symbols.len());
        self.symbols.push(decl);
        Ok(self.symbols.len() - 1)
    }

    fn phase_of(&self, spec: &Toml, what: &str) -> Result<Option<usize>> {
        match text_of(spec, "phase").and_then(|p| self.phases.iter().position(|q| q == p)) {
            Some(index) => Ok(Some(index)),
            None => model_err(format!("{what}: 'phase' must be one of {:?}", self.phases)),
        }
    }

    fn entity_of(&self, spec: &Toml, what: &str) -> Result<Option<usize>> {
        match spec.get("entity") {
            None => Ok(None),
            Some(value) => match value.as_str().and_then(|name| self.entity_index.get(name)) {
                Some(index) => Ok(Some(*index)),
                None => model_err(format!("{what}: unknown entity {}", value.to_string_lossy())),
            },
        }
    }

    fn unit_or_one(&self, spec: &Toml, what: &str, ty: Ty) -> Result<Unit> {
        unit_of(spec, what, if ty == Ty::Bool { Some("1") } else { None })
    }
}

/// Loads a model from a folder containing `model.toml`, or from the manifest itself.
pub fn load_model(path: &Path) -> Result<Model> {
    let manifest = if path.is_dir() { path.join("model.toml") } else { path.to_path_buf() };
    let root = manifest.parent().map(Path::to_path_buf).unwrap_or_default();

    // ---- read and merge files; hash the bytes that define the model
    let mut digest = Sha256::new();
    let mut read = |file: &Path, relative: &str| -> Result<Toml> {
        let bytes = std::fs::read(file).map_err(|e| Error::Model(format!("cannot read {}: {e}", file.display())))?;
        digest.update(relative.as_bytes());
        digest.update([0u8]);
        digest.update(&bytes);
        digest.update([0u8]);
        let text = std::str::from_utf8(&bytes).map_err(|_| Error::Model(format!("{relative} is not UTF-8")))?;
        text.parse::<Toml>().map_err(|e| Error::Model(format!("{relative}: {e}")))
    };
    let manifest_name = manifest.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let first = read(&manifest, &manifest_name)?;
    let mut documents = vec![];
    if let Some(Value::Array(files)) = first.get("model").and_then(|m| m.get("files")) {
        for file in files {
            let Some(file) = file.as_str() else { return model_err("model.files must be a list of file names") };
            documents.push(read(&root.join(file), &relative_name(file))?);
        }
    }
    documents.insert(0, first);

    let mut merged: Vec<Toml> = SECTIONS.iter().map(|_| Toml::new()).collect();
    let section = |name: &str| SECTIONS.iter().position(|s| *s == name).unwrap();
    for doc in documents {
        for (name, content) in doc {
            let Some(index) = SECTIONS.iter().position(|s| *s == name) else {
                return model_err(format!("unknown section [{name}]"));
            };
            let Value::Table(content) = content else { return model_err(format!("[{name}] must be a table")) };
            for (key, spec) in content {
                if index != 0 && merged[index].contains_key(&key) {
                    return model_err(format!("{name}.{key} is declared twice"));
                }
                merged[index].insert(key, spec);
            }
        }
    }

    let head = &merged[0];
    if head.get("format").and_then(Value::as_integer) != Some(0) {
        return model_err("this loader reads model format 0 only");
    }
    let (Some(id), Some(currency), Some(minor), Some(step), Some(Value::Array(phases))) = (
        text_of(head, "id"),
        text_of(head, "currency"),
        head.get("minor_units").and_then(Value::as_integer),
        text_of(head, "step"),
        head.get("phases"),
    ) else {
        return model_err("[model] needs id, currency, minor_units, step and phases");
    };
    let phases: Vec<String> = phases.iter().filter_map(|p| p.as_str().map(str::to_string)).collect();
    let step_unit = Unit::parse(step).map_err(|e| Error::Model(format!("[model] step: {e}")))?;

    let mut sector_entities: Vec<Option<String>> = Vec::new();
    let mut sector_names: Vec<String> = Vec::new();
    for (name, spec) in &merged[section("sector")] {
        let spec = table_of(spec, &format!("sector {name}"))?;
        sector_names.push(name.clone());
        sector_entities.push(text_of(spec, "entity").map(str::to_string));
    }
    let sector_index = |name: &str| sector_names.iter().position(|s| s == name);

    struct RawInstrument {
        name: String,
        unit: Unit,
        issuer: usize,
    }
    let mut raw_instruments = Vec::new();
    for (name, spec) in &merged[section("instrument")] {
        let what = format!("instrument {name}");
        let spec = table_of(spec, &what)?;
        let Some(issuer) = text_of(spec, "issuer").and_then(sector_index) else {
            return model_err(format!("{what}: issuer must be a declared sector"));
        };
        raw_instruments.push(RawInstrument { name: name.clone(), unit: unit_of(spec, &what, None)?, issuer });
    }

    let mut entities = Vec::new();
    let mut entity_index = HashMap::new();
    let mut data_files = Vec::new();
    for (name, spec) in &merged[section("entity")] {
        let (entity, bytes, relative) = read_entity(&root, name, table_of(spec, &format!("entity {name}"))?)?;
        entity_index.insert(name.clone(), entities.len());
        entities.push(entity);
        data_files.push((relative, bytes));
    }
    for (relative, bytes) in &data_files {
        digest.update(relative.as_bytes());
        digest.update([0u8]);
        digest.update(bytes);
        digest.update([0u8]);
    }
    let mut sectors = Vec::new();
    for (name, entity) in sector_names.iter().zip(&sector_entities) {
        let entity = match entity {
            None => None,
            Some(e) => match entity_index.get(e) {
                Some(index) => Some(*index),
                None => return model_err(format!("sector {name}: unknown entity {e:?}")),
            },
        };
        sectors.push(Sector { name: name.clone(), entity });
    }

    let mut streams: Vec<(String, u32)> = Vec::new();
    for (name, _) in &merged[section("stream")] {
        let stream_id = fnv1a32(name);
        if streams.iter().any(|(_, existing)| *existing == stream_id) {
            return model_err(format!("stream {name}: id collides with another stream; rename one"));
        }
        streams.push((name.clone(), stream_id));
    }

    let mut tables = Vec::new();
    let mut table_index = HashMap::new();
    for (name, spec) in &merged[section("table")] {
        let what = format!("table {name}");
        let spec = table_of(spec, &what)?;
        if text_of(spec, "kind") != Some("marginal") {
            return model_err(format!("{what}: only kind = \"marginal\" exists in format 0"));
        }
        let mut bands = Vec::new();
        if let Some(Value::Array(items)) = spec.get("bands") {
            for band in items {
                let band = table_of(band, &what)?;
                let (Some(from), Some(rate)) = (band.get("from"), band.get("rate")) else {
                    return model_err(format!("{what}: each band needs 'from' and 'rate'"));
                };
                bands.push((formula_text(from), formula_text(rate)));
            }
        }
        if bands.is_empty() {
            return model_err(format!("{what}: needs at least one band"));
        }
        table_index.insert(name.clone(), tables.len());
        tables.push(Table { name: name.clone(), unit: unit_of(spec, &what, None)?, bands });
    }

    // ---- declarations
    let mut taken: Vec<String> = table_index.keys().cloned().collect();
    taken.extend(streams.iter().map(|(n, _)| n.clone()));
    taken.extend(entity_index.keys().cloned());
    let mut loader =
        Loader { minor, phases: phases.clone(), symbols: Vec::new(), sym_index: HashMap::new(), taken, entity_index: entity_index.clone() };

    for (ent_name, ent_spec) in &merged[section("entity")] {
        let entity = entity_index[ent_name];
        let Some(columns) = table_of(ent_spec, "entity")?.get("columns") else { continue };
        for (name, spec) in table_of(columns, &format!("entity {ent_name} columns"))? {
            let what = format!("column {name}");
            let spec = table_of(spec, &what)?;
            let (ty, money) = type_of(spec, &what)?;
            if entities[entity].column(name).is_none() {
                return model_err(format!("{what}: not found in the data of entity {ent_name}"));
            }
            let unit = loader.unit_or_one(spec, &what, ty)?;
            loader.declare(Decl {
                name: name.clone(), kind: Kind::Column, ty, unit, money, entity: Some(entity), phase: None, expr: None,
                initial: None, range: None, spec: spec.clone(),
            })?;
        }
    }

    for (name, spec) in &merged[section("param")] {
        let what = format!("param {name}");
        let spec = table_of(spec, &what)?;
        let (ty, money) = type_of(spec, &what)?;
        let unit = loader.unit_or_one(spec, &what, ty)?;
        loader.declare(Decl {
            name: name.clone(), kind: Kind::Param, ty, unit, money, entity: None, phase: None, expr: None, initial: None,
            range: range_of(spec, money, loader.minor, &what)?, spec: spec.clone(),
        })?;
    }

    for (name, spec) in &merged[section("lever")] {
        let what = format!("lever {name}");
        let spec = table_of(spec, &what)?;
        let (ty, money) = type_of(spec, &what)?;
        let Some(default) = spec.get("default") else { return model_err(format!("{what}: missing 'default'")) };
        let unit = loader.unit_or_one(spec, &what, ty)?;
        loader.declare(Decl {
            name: name.clone(), kind: Kind::Lever, ty, unit, money, entity: None, phase: None, expr: None,
            initial: Some(default.clone()), range: range_of(spec, money, loader.minor, &what)?, spec: spec.clone(),
        })?;
    }

    for (name, spec) in &merged[section("var")] {
        let what = format!("var {name}");
        let spec = table_of(spec, &what)?;
        let (ty, money) = type_of(spec, &what)?;
        let Some(expr) = spec.get("expr") else { return model_err(format!("{what}: missing 'expr'")) };
        let unit = loader.unit_or_one(spec, &what, ty)?;
        loader.declare(Decl {
            name: name.clone(), kind: Kind::Var, ty, unit, money, entity: loader.entity_of(spec, &what)?,
            phase: loader.phase_of(spec, &what)?, expr: Some(formula_text(expr)), initial: spec.get("initial").cloned(),
            range: range_of(spec, money, loader.minor, &what)?, spec: spec.clone(),
        })?;
    }

    for (name, spec) in &merged[section("state")] {
        let what = format!("state {name}");
        let spec = table_of(spec, &what)?;
        let (ty, money) = type_of(spec, &what)?;
        let (Some(next), Some(initial)) = (spec.get("next"), spec.get("initial")) else {
            return model_err(format!("{what}: needs both 'initial' and 'next'"));
        };
        let unit = loader.unit_or_one(spec, &what, ty)?;
        loader.declare(Decl {
            name: name.clone(), kind: Kind::State, ty, unit, money, entity: loader.entity_of(spec, &what)?,
            phase: loader.phase_of(spec, &what)?, expr: Some(formula_text(next)), initial: Some(initial.clone()),
            range: range_of(spec, money, loader.minor, &what)?, spec: spec.clone(),
        })?;
    }

    let instrument_index = |name: &str| raw_instruments.iter().position(|i| i.name == name);
    let mut accounts: Vec<Account> = Vec::new();
    for (name, spec) in &merged[section("account")] {
        let what = format!("account {name}");
        let spec = table_of(spec, &what)?;
        let (Some(sector), Some(instrument)) =
            (text_of(spec, "sector").and_then(sector_index), text_of(spec, "instrument").and_then(instrument_index))
        else {
            return model_err(format!("{what}: needs a declared 'sector' and 'instrument'"));
        };
        if accounts.iter().any(|a| a.sector == sector && a.instrument == instrument) {
            return model_err(format!("{what}: sector {} already has an account in {}", sector_names[sector], raw_instruments[instrument].name));
        }
        let is_issuer = raw_instruments[instrument].issuer == sector;
        if is_issuer == spec.contains_key("initial") {
            return model_err(format!("{what}: holders need 'initial'; the issuer's balance is derived"));
        }
        let entity = sectors[sector].entity;
        let mut unit = raw_instruments[instrument].unit.clone();
        if let Some(entity) = entity {
            unit = units::div(&Some(unit), &Some(Unit::base(&entities[entity].name)));
        }
        let sym = loader.declare(Decl {
            name: name.clone(), kind: Kind::Account, ty: Ty::Int, unit, money: true, entity, phase: None, expr: None,
            initial: spec.get("initial").cloned(), range: range_of(spec, true, loader.minor, &what)?, spec: spec.clone(),
        })?;
        accounts.push(Account { sym, sector, instrument });
    }
    let account_of = |accounts: &[Account], sector: usize, instrument: usize| {
        accounts.iter().find(|a| a.sector == sector && a.instrument == instrument).map(|a| a.sym)
    };

    let mut flows = Vec::new();
    for (name, spec) in &merged[section("flow")] {
        let what = format!("flow {name}");
        let spec = table_of(spec, &what)?;
        let ends = (text_of(spec, "from").and_then(sector_index), text_of(spec, "to").and_then(sector_index));
        let (Some(src), Some(dst)) = ends else {
            return model_err(format!("{what}: 'from' and 'to' must be two different declared sectors"));
        };
        if src == dst {
            return model_err(format!("{what}: 'from' and 'to' must be two different declared sectors"));
        }
        let instrument = match spec.get("instrument") {
            None if !raw_instruments.is_empty() => Some(0),
            None => None,
            Some(value) => value.as_str().and_then(instrument_index),
        };
        let Some(instrument) = instrument else { return model_err(format!("{what}: unknown instrument")) };
        let (Some(src_account), Some(dst_account)) =
            (account_of(&accounts, src, instrument), account_of(&accounts, dst, instrument))
        else {
            return model_err(format!("{what}: both sectors need an account in {}", raw_instruments[instrument].name));
        };
        let entity = match (sectors[src].entity, sectors[dst].entity) {
            (Some(_), Some(_)) => return model_err(format!("{what}: flows between two per-record sectors are not in format 0")),
            (a, b) => a.or(b),
        };
        let mut unit = units::div(&Some(raw_instruments[instrument].unit.clone()), &Some(step_unit.clone()));
        if let Some(entity) = entity {
            unit = units::div(&Some(unit), &Some(Unit::base(&entities[entity].name)));
        }
        if spec.contains_key("unit") && unit_of(spec, &what, None)? != unit {
            return model_err(format!("{what}: unit must be {}", units::fmt(&Some(unit))));
        }
        let Some(expr) = spec.get("expr") else { return model_err(format!("{what}: missing 'expr'")) };
        let sym = loader.declare(Decl {
            name: name.clone(), kind: Kind::Flow, ty: Ty::Int, unit, money: true, entity,
            phase: loader.phase_of(spec, &what)?, expr: Some(formula_text(expr)), initial: spec.get("initial").cloned(),
            range: range_of(spec, true, loader.minor, &what)?, spec: spec.clone(),
        })?;
        flows.push(Flow { sym, src_account, dst_account });
    }

    let mut instruments = Vec::new();
    for (index, raw) in raw_instruments.iter().enumerate() {
        let Some(issuer_account) = account_of(&accounts, raw.issuer, index) else {
            return model_err(format!("instrument {}: the issuer {} needs an account", raw.name, sector_names[raw.issuer]));
        };
        if sectors[raw.issuer].entity.is_some() {
            return model_err(format!("instrument {}: the issuer cannot be a per-record sector", raw.name));
        }
        instruments.push(Instrument { name: raw.name.clone(), unit: raw.unit.clone(), issuer: raw.issuer, issuer_account });
    }

    Ok(Model {
        root,
        id: id.to_string(),
        currency: currency.to_string(),
        minor,
        step_unit,
        phases,
        sectors,
        instruments,
        entities,
        streams,
        tables,
        symbols: loader.symbols,
        accounts,
        flows,
        model_hash: digest.finalize().into(),
        sym_index: loader.sym_index,
        table_index,
        entity_index,
    })
}

/// A formula written in a TOML file. Text is used as is; a bare number or true/false is
/// turned into the text the oracle would see.
fn formula_text(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Boolean(b) => pyfmt::bool_str(*b).to_string(),
        other => other.to_string_lossy(),
    }
}

/// A run to perform: a model plus seed, parameter preset, overrides and scheduled commands.
#[derive(Clone, Debug)]
pub struct Scenario {
    pub name: String,
    pub model: Model,
    pub seed: u64,
    pub steps: u64,
    pub preset: String,
    pub params: Vec<(String, Value)>,
    pub levers: Vec<(String, Value)>,
    /// (step, lever, value) in file order. Applied before that step runs; for one lever
    /// in one step the last entry wins.
    pub commands: Vec<(u64, String, Value)>,
}

pub fn load_scenario(path: &Path) -> Result<Scenario> {
    let text = std::fs::read_to_string(path).map_err(|e| Error::Model(format!("cannot read {}: {e}", path.display())))?;
    let doc = text.parse::<Toml>().map_err(|e| Error::Model(format!("{}: {e}", path.display())))?;
    let Some(Value::Table(head)) = doc.get("scenario") else { return model_err("scenario file needs a [scenario] table") };
    let (Some(model_path), Some(seed), Some(steps)) =
        (text_of(head, "model"), head.get("seed").and_then(Value::as_integer), head.get("steps").and_then(Value::as_integer))
    else {
        return model_err("[scenario] needs model, seed and steps");
    };
    let pairs = |key: &str| -> Vec<(String, Value)> {
        match doc.get(key) {
            Some(Value::Table(t)) => t.iter().map(|(k, v)| (k.clone(), v.clone())).collect(),
            _ => Vec::new(),
        }
    };
    let mut commands = Vec::new();
    if let Some(Value::Array(items)) = doc.get("command") {
        for item in items {
            let item = table_of(item, "command")?;
            let (Some(step), Some(Value::Table(set))) = (item.get("step").and_then(Value::as_integer), item.get("set")) else {
                return model_err("each [[command]] needs 'step' and 'set'");
            };
            if step < 0 {
                continue; // can never be reached; the oracle keeps it and never applies it
            }
            for (lever, value) in set {
                commands.push((step as u64, lever.clone(), value.clone()));
            }
        }
    }
    let base = path.parent().unwrap_or(Path::new("."));
    Ok(Scenario {
        name: path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default(),
        model: load_model(&base.join(model_path))?,
        seed: seed as u64,
        steps: steps.max(0) as u64,
        preset: text_of(head, "preset").unwrap_or("central").to_string(),
        params: pairs("params"),
        levers: pairs("levers"),
        commands,
    })
}
