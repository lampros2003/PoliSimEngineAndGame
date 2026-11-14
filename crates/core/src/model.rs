//! Model-file format 0: loading and structural validation.
//!
//! A port of oracle/polisim_oracle/model.py. Formulas are compiled later, by the
//! simulation.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};
use toml::{Table as Toml, Value};

use crate::error::{Error, Result, model_err};
use crate::program::{Ty, Val};
use crate::pyfmt;
use crate::rng::fnv1a32;
use crate::units::{self, Unit};

/// Function names of the formula language. With the five keywords they are reserved.
pub const FUNCTIONS: [&str; 28] = [
    "abs",
    "ceil",
    "clamp",
    "cohort_shift",
    "coord",
    "div",
    "exp",
    "floor",
    "largest",
    "marginal",
    "max",
    "min",
    "mod",
    "muldiv",
    "per_step",
    "prev",
    "rand",
    "round",
    "safe_div",
    "select",
    "smallest",
    "sum",
    "sum_by",
    "times_step",
    "wcount",
    "wcount_by",
    "wsum",
    "wsum_by",
];
const KEYWORDS: [&str; 5] = ["and", "or", "not", "true", "false"];
const SECTIONS: [&str; 17] = [
    "model",
    "legislature",
    "dim",
    "sector",
    "instrument",
    "entity",
    "stream",
    "table",
    "param",
    "lever",
    "var",
    "state",
    "flow",
    "account",
    "renamed",
    "situation",
    "dilemma",
];
/// Format 1: the most cells one value may have.
pub const MAX_CELLS: usize = 16_777_216;

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
    /// Format 1: one value per cell of these dimensions (indices into `Model::dims`).
    pub dims: Vec<usize>,
    /// Format 1: a dimensioned parameter's or initial value's CSV columns, as text per cell
    /// in row-major order.
    pub data: Vec<(String, Vec<String>)>,
    /// Format 1 (S4.4): a weight state's rake, instead of a `next` formula.
    pub rake: Option<Rake>,
}

/// Format 1 (S4.4): iterative proportional updating of a weight state.
#[derive(Clone, Debug)]
pub struct Rake {
    /// National formula, bool: the weights change only in steps where it is true.
    pub when: String,
    pub passes: u32,
    pub margins: Vec<Margin>,
}

#[derive(Clone, Debug)]
pub struct Margin {
    /// A national param, var or state with dimensions.
    pub target: String,
    pub slots: Vec<Slot>,
}

#[derive(Clone, Debug)]
pub struct Slot {
    /// Record formula: units of the target per unit of weight.
    pub count: String,
    /// Record formulas, one per dimension of the target: the record's member along it.
    pub at: Vec<String>,
}

impl Decl {
    /// Held as a column: one value per record of an entity, or per cell of its dimensions.
    pub fn columnar(&self) -> bool {
        self.entity.is_some() || !self.dims.is_empty()
    }

    pub fn data_column(&self, name: &str) -> Option<&[String]> {
        self.data.iter().find(|(n, _)| n == name).map(|(_, cells)| cells.as_slice())
    }
}

/// Format 1: a named, ordered set of members.
#[derive(Clone, Debug)]
pub struct Dim {
    pub name: String,
    /// `Some(first)` for a range of whole numbers, `None` for a list of names.
    pub first: Option<i64>,
    /// Member names of a list; members of a range as text.
    pub members: Vec<String>,
    pub labels: Vec<String>,
}

impl Dim {
    pub fn size(&self) -> usize {
        self.members.len()
    }

    /// Position of a member written in a data file.
    pub fn position(&self, text: &str) -> Option<usize> {
        match self.first {
            Some(first) => {
                let value: i64 = text.parse().ok()?;
                let pos = value.checked_sub(first)?;
                (0..self.size() as i64).contains(&pos).then_some(pos as usize)
            }
            None => self.members.iter().position(|m| m == text),
        }
    }
}

#[derive(Clone, Debug)]
pub struct Entity {
    pub name: String,
    pub ids: Vec<u64>,
    /// From the data. A run's current weights are the simulation's: see `weight_state`.
    pub weights: Vec<i64>,
    /// Format 1 (S4.4): the record-level state that holds the weights, if they change.
    pub weight_state: Option<String>,
    header: Vec<String>,
    /// Every CSV column as text, in header order.
    raw: Vec<TextColumn>,
}

/// Stage S10: a column of text cells in one buffer, so that a model with many records is
/// quick to load, copy and drop (one allocation a column, not one a cell).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct TextColumn {
    text: String,
    /// Where each cell ends in `text`.
    ends: Vec<u32>,
}

impl TextColumn {
    fn push(&mut self, cell: &str) -> Result<()> {
        self.text.push_str(cell);
        let end = u32::try_from(self.text.len()).map_err(|_| Error::Model("a data column is too large".to_string()))?;
        self.ends.push(end);
        Ok(())
    }

    pub fn len(&self) -> usize {
        self.ends.len()
    }

    pub fn is_empty(&self) -> bool {
        self.ends.is_empty()
    }

    pub fn get(&self, i: usize) -> &str {
        let start = if i == 0 { 0 } else { self.ends[i - 1] as usize };
        &self.text[start..self.ends[i] as usize]
    }

    pub fn iter(&self) -> impl ExactSizeIterator<Item = &str> {
        (0..self.len()).map(|i| self.get(i))
    }
}

impl Entity {
    pub fn len(&self) -> usize {
        self.ids.len()
    }

    pub fn is_empty(&self) -> bool {
        self.ids.is_empty()
    }

    pub fn column(&self, name: &str) -> Option<&TextColumn> {
        // The last of two columns with one name wins, as in the oracle's dictionary.
        self.header.iter().rposition(|h| h == name).map(|i| &self.raw[i])
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
    /// Stage S7.1: the mods applied on top of the model's own files, in order.
    pub mods: Vec<ModInfo>,
    /// Stage S7.1: what loading the mods is worth telling the player (an element patched
    /// by two mods, for instance).
    pub mod_notes: Vec<String>,
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
    /// Format 1: dimensions in declaration order.
    pub dims: Vec<Dim>,
    pub dim_index: HashMap<String, usize>,
    pub format: i64,
    /// Format 1 (S5.4): the legislature that votes on lever changes.
    pub legislature: Option<Legislature>,
    /// Stage S7.0: names a value had in earlier versions of the model, each with the name it
    /// has now (chains followed), sorted by the old name. Saves made before a rename carry
    /// the value across.
    pub renamed: Vec<(String, String)>,
    /// Stage S9.1: each dilemma and its answers, in the order declared.
    pub dilemmas: Vec<DilemmaInfo>,
}

/// Stage S9.1: a question put to the player, as the loader keeps it for the catalogue and
/// for checking answers. Its lever is `name`; the elements it makes carry `dilemma = name`.
#[derive(Clone, Debug, PartialEq)]
pub struct DilemmaInfo {
    pub name: String,
    pub label: String,
    pub doc: String,
    pub again_after: Option<i64>,
    pub options: Vec<DilemmaOption>,
}

/// Stage S9.1: one answer to a dilemma.
#[derive(Clone, Debug, PartialEq)]
pub struct DilemmaOption {
    pub name: String,
    pub label: String,
    pub doc: String,
    pub months: Option<i64>,
}

/// Format 1 (S5.4): symbol indices of the seats each bloc holds (whole numbers), whether it
/// governs (true/false) and its position (real: left below zero, right above), all over
/// one dimension of blocs.
#[derive(Clone, Copy, Debug)]
pub struct Legislature {
    pub seats: usize,
    pub governing: usize,
    pub position: usize,
}

impl Model {
    /// Number of cells of a list of dimensions (1 for none).
    pub fn cell_count(&self, dims: &[usize]) -> usize {
        dims.iter().map(|d| self.dims[*d].size()).product()
    }

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
            // Stage S10: a plain decimal is read as typed, without printing the number back.
            let exact = match text.and_then(|t| exact_minor_units_of_text(t.trim(), minor)) {
                Some(exact) => exact,
                None => exact_minor_units(f, minor),
            };
            match exact {
                Some(v) => v,
                None => return model_err(format!("{what}: {} has more decimal places than the currency", show(raw))),
            }
        }
        (Number::Whole(i), false) => i,
        (Number::Real(_), false) => return model_err(format!("{what}: expected a whole number, got {}", show(raw))),
    };
    Ok(Val::I(value))
}

/// `f` major units in minor units, if that is a whole number. The number is read as the
/// shortest decimal that gives this float (Python's `repr`), which is what was typed, and
/// scaled exactly: 2301745961.03 pounds is 230174596103 pence, although
/// `2301745961.03 * 100.0` is 230174596102.99997.
/// Stage S10: what [`exact_minor_units`] gives for the number this text reads as, worked out
/// from the text itself when it is a plain decimal (a sign, digits, a point and digits) of at
/// most 15 significant digits; `None` for any other text. For such a decimal the shortest
/// text that reads back as the same float has the same digits (any shorter decimal differs by
/// more than half a unit in the last place), so the two agree; the other is far slower.
fn exact_minor_units_of_text(text: &str, minor: i64) -> Option<Option<i64>> {
    let negative = text.starts_with('-');
    let body = text.strip_prefix(['-', '+']).unwrap_or(text);
    let (whole, fraction) = body.split_once('.').unwrap_or((body, ""));
    let digits_only = |s: &str| s.bytes().all(|b| b.is_ascii_digit());
    if whole.is_empty() || (body.contains('.') && fraction.is_empty()) || !digits_only(whole) || !digits_only(fraction)
    {
        return None;
    }
    let digits = format!("{whole}{fraction}");
    if digits.trim_start_matches('0').len() > 15 {
        return None;
    }
    let value: i128 = digits.parse().ok()?;
    let scaled = (if negative { -value } else { value }).checked_mul(minor as i128)?;
    let Some(divisor) = 10i128.checked_pow(fraction.len() as u32) else { return Some(None) };
    Some(if scaled % divisor != 0 { None } else { i64::try_from(scaled / divisor).ok() })
}

fn exact_minor_units(f: f64, minor: i64) -> Option<i64> {
    let text = crate::pyfmt::float_repr(f);
    let (mantissa, exponent) = match text.split_once('e') {
        Some((m, e)) => (m, e.parse::<i32>().ok()?),
        None => (text.as_str(), 0),
    };
    let decimals = mantissa.split_once('.').map_or(0, |(_, frac)| frac.len()) as i32;
    let digits: String = mantissa.chars().filter(|c| *c == '-' || c.is_ascii_digit()).collect();
    // The value is digits * 10^power.
    let power = exponent - decimals;
    let scaled = digits.parse::<i128>().ok()?.checked_mul(minor as i128)?;
    let whole = if power >= 0 {
        scaled.checked_mul(10i128.checked_pow(power as u32)?)?
    } else {
        let divisor = 10i128.checked_pow(power.unsigned_abs())?;
        if scaled % divisor != 0 {
            return None;
        }
        scaled / divisor
    };
    i64::try_from(whole).ok()
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

/// Stage S10: the records of a CSV text, as `parse_csv` reads them, given one at a time with
/// its fields (one buffer, reused).
fn each_csv_row(text: &str, mut row: impl FnMut(&[String]) -> Result<()>) -> Result<()> {
    let mut fields: Vec<String> = Vec::new();
    let mut used = 0usize;
    let mut quoted = false;
    let mut chars = text.chars().peekable();
    // The field being filled: fields[used], cleared when first used.
    fn field(fields: &mut Vec<String>, used: usize) -> &mut String {
        if fields.len() <= used {
            fields.resize_with(used + 1, String::new);
        }
        &mut fields[used]
    }
    let mut started = false;
    let mut end_row = |fields: &mut Vec<String>, used: &mut usize, started: &mut bool| -> Result<()> {
        if !*started {
            field(fields, *used).clear();
        }
        let n = *used + 1;
        let blank = n == 1 && fields[0].is_empty();
        *used = 0;
        *started = false;
        if blank { Ok(()) } else { row(&fields[..n]) }
    };
    while let Some(c) = chars.next() {
        if !started {
            field(&mut fields, used).clear();
            started = true;
        }
        if quoted {
            if c == '"' {
                if chars.peek() == Some(&'"') {
                    chars.next();
                    fields[used].push('"');
                } else {
                    quoted = false;
                }
            } else {
                fields[used].push(c);
            }
        } else if c == '"' && fields[used].is_empty() {
            quoted = true;
        } else if c == ',' {
            used += 1;
            started = false;
        } else if c == '\n' {
            end_row(&mut fields, &mut used, &mut started)?;
        } else if c == '\r' && chars.peek() == Some(&'\n') {
            // handled by the line feed that follows
        } else {
            fields[used].push(c);
        }
    }
    if started || used > 0 {
        end_row(&mut fields, &mut used, &mut started)?;
    }
    Ok(())
}

fn read_entity(root: &Path, name: &str, spec: &Toml) -> Result<(Entity, Vec<u8>, String)> {
    let what = format!("entity {name}");
    let state = match spec.get("weight") {
        Some(Value::Table(t)) => match (t.len(), t.get("state").and_then(Value::as_str)) {
            (1, Some(name)) => Some(name.to_string()),
            _ => return model_err(format!("{what}: 'weight' is a column name or {{ state = \"<name>\" }}")),
        },
        _ => None,
    };
    let weight = if state.is_some() { Some("") } else { text_of(spec, "weight") };
    let (Some(data), Some(id), Some(weight)) = (text_of(spec, "data"), text_of(spec, "id"), weight) else {
        return model_err(format!("{what}: needs 'data', 'id' and 'weight'"));
    };
    let path = root.join(data);
    let bytes =
        std::fs::read(&path).map_err(|e| Error::Model(format!("{what}: cannot read {}: {e}", path.display())))?;
    let text = std::str::from_utf8(&bytes).map_err(|_| Error::Model(format!("{what}: {data} is not UTF-8")))?;
    let mut header: Option<Vec<String>> = None;
    let mut raw: Vec<TextColumn> = Vec::new();
    let mut line = 1usize;
    each_csv_row(text, |row| {
        let Some(header) = &header else {
            header = Some(row.to_vec());
            raw = vec![TextColumn::default(); row.len()];
            return Ok(());
        };
        line += 1;
        if row.len() != header.len() {
            return model_err(format!(
                "{what}: row {line} of {data} has {} fields, expected {}",
                row.len(),
                header.len()
            ));
        }
        for (column, cell) in raw.iter_mut().zip(row) {
            column.push(cell)?;
        }
        Ok(())
    })?;
    let header = header.unwrap_or_default();
    if line < 2 {
        return model_err(format!("{what}: {} has no rows", path.display()));
    }
    let mut entity =
        Entity { name: name.to_string(), ids: Vec::new(), weights: Vec::new(), weight_state: state, header, raw };
    let needed: &[&str] = if entity.weight_state.is_some() { &[id] } else { &[id, weight] };
    for &needed in needed {
        if entity.column(needed).is_none() {
            return model_err(format!("{what}: column {needed:?} not found in {data}"));
        }
    }
    let whole = |column: &str, label: &str| -> Result<Vec<i64>> {
        entity
            .column(column)
            .unwrap()
            .iter()
            .map(|cell| match convert(Raw::Text(cell), Ty::Int, false, 1, label)? {
                Val::I(v) => Ok(v),
                _ => unreachable!("whole-number conversion"),
            })
            .collect()
    };
    let ids = whole(id, &format!("{what} id"))?;
    // Weights held by a state come from its initial value when a run starts.
    let weights =
        if entity.weight_state.is_some() { vec![1; ids.len()] } else { whole(weight, &format!("{what} weight"))? };
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
/// Stage S7.1: whether an element's declaration reads a data file of its own.
fn uses_data(spec: &Value) -> bool {
    let Value::Table(spec) = spec else { return false };
    spec.contains_key("data")
        || matches!(spec.get("initial"), Some(Value::Table(initial)) if initial.contains_key("data"))
}

fn relative_name(path: &str) -> String {
    path.split(['/', '\\']).filter(|part| !part.is_empty() && *part != ".").collect::<Vec<_>>().join("/")
}

struct Loader {
    minor: i64,
    format: i64,
    root: PathBuf,
    dims: Vec<Dim>,
    dim_index: HashMap<String, usize>,
    /// Data files of dimensioned elements, by path as written: parsed rows and bytes.
    cell_files: BTreeMap<String, (Vec<Vec<String>>, Vec<u8>)>,
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

    /// Format 1: the `dims` of an element, checked.
    fn dims_of(&self, spec: &Toml, kind: Kind, what: &str) -> Result<Vec<usize>> {
        let Some(value) = spec.get("dims") else { return Ok(Vec::new()) };
        if self.format != 1 {
            return model_err(format!("{what}: dimensions need format = 1"));
        }
        if !matches!(kind, Kind::Param | Kind::Var | Kind::State) {
            return model_err(format!("{what}: a {} cannot have dimensions in format 1", kind.name()));
        }
        if spec.get("entity").is_some() {
            return model_err(format!("{what}: an element cannot have both an entity and dimensions"));
        }
        let names: Vec<&str> = match value {
            Value::Array(items) => items.iter().filter_map(Value::as_str).collect(),
            _ => Vec::new(),
        };
        let mut dims = Vec::new();
        for name in &names {
            match self.dim_index.get(*name) {
                Some(index) if !dims.contains(index) => dims.push(*index),
                _ => return model_err(format!("{what}: 'dims' must list declared dimensions, each once")),
            }
        }
        if dims.is_empty() || dims.len() != value.as_array().map_or(0, Vec::len) {
            return model_err(format!("{what}: 'dims' must list declared dimensions, each once"));
        }
        let mut cells: usize = 1;
        for d in &dims {
            cells = cells.saturating_mul(self.dims[*d].size());
        }
        if cells > MAX_CELLS {
            return model_err(format!("{what}: more than {MAX_CELLS} cells"));
        }
        Ok(dims)
    }

    /// Format 1: the named columns of a data file, as text per cell in row-major order of `dims`.
    fn cell_data(
        &mut self,
        dims: &[usize],
        file: &str,
        columns: &[String],
        what: &str,
    ) -> Result<Vec<(String, Vec<String>)>> {
        if !self.cell_files.contains_key(file) {
            let path = self.root.join(file);
            let Ok(bytes) = std::fs::read(&path) else {
                return model_err(format!("{what}: data file {file} not found"));
            };
            let rows = parse_csv(&String::from_utf8_lossy(&bytes));
            self.cell_files.insert(file.to_string(), (rows, bytes));
        }
        let rows = &self.cell_files[file].0;
        let Some(header) = rows.first() else { return model_err(format!("{what}: {file} is empty")) };
        let find = |name: &str| header.iter().position(|h| h == name);
        let mut dim_cols = Vec::new();
        for d in dims {
            match find(&self.dims[*d].name) {
                Some(i) => dim_cols.push(i),
                None => return model_err(format!("{what}: {file} has no column {:?}", self.dims[*d].name)),
            }
        }
        let mut value_cols = Vec::new();
        for c in columns {
            match find(c) {
                Some(i) => value_cols.push(i),
                None => return model_err(format!("{what}: {file} has no column {c:?}")),
            }
        }
        let mut strides = vec![1usize; dims.len()];
        for k in (0..dims.len().saturating_sub(1)).rev() {
            strides[k] = strides[k + 1] * self.dims[dims[k + 1]].size();
        }
        let count: usize = dims.iter().map(|d| self.dims[*d].size()).product();
        let mut out: Vec<Vec<Option<String>>> = vec![vec![None; count]; columns.len()];
        for row in &rows[1..] {
            let mut flat = 0;
            for (k, d) in dims.iter().enumerate() {
                let text = row.get(dim_cols[k]).map(|t| t.trim()).unwrap_or("");
                match self.dims[*d].position(text) {
                    Some(pos) => flat += pos * strides[k],
                    None => {
                        return model_err(format!(
                            "{what}: {file}: {text:?} is not a member of {}",
                            self.dims[*d].name
                        ));
                    }
                }
            }
            if out[0][flat].is_some() {
                return model_err(format!("{what}: {file}: a cell appears twice"));
            }
            for (j, col) in value_cols.iter().enumerate() {
                out[j][flat] = Some(row.get(*col).cloned().unwrap_or_default());
            }
        }
        let mut result = Vec::new();
        for (j, c) in columns.iter().enumerate() {
            let mut cells = Vec::with_capacity(count);
            for cell in &out[j] {
                match cell {
                    Some(text) => cells.push(text.clone()),
                    None => return model_err(format!("{what}: {file}: some cells are missing")),
                }
            }
            result.push((c.clone(), cells));
        }
        Ok(result)
    }

    /// Format 1: reads the CSV behind a dimensioned parameter or initial value.
    fn data_for(
        &mut self,
        kind: Kind,
        dims: &[usize],
        spec: &Toml,
        initial: Option<&Value>,
        what: &str,
    ) -> Result<Vec<(String, Vec<String>)>> {
        if dims.is_empty() {
            return Ok(Vec::new());
        }
        if kind == Kind::Param {
            if let Some(file) = spec.get("data") {
                let Some(file) = file.as_str() else { return model_err(format!("{what}: 'data' must be a path")) };
                let columns: Vec<String> = match spec.get("columns") {
                    Some(Value::Table(t)) => t.values().filter_map(|v| v.as_str().map(str::to_string)).collect(),
                    _ => vec![text_of(spec, "column").unwrap_or("value").to_string()],
                };
                return self.cell_data(dims, file, &columns, what);
            }
            return Ok(Vec::new());
        }
        if let Some(Value::Table(t)) = initial {
            if let Some(file) = t.get("data").and_then(Value::as_str) {
                let column = text_of(t, "column").unwrap_or("value").to_string();
                return self.cell_data(dims, file, &[column], what);
            }
        }
        Ok(Vec::new())
    }

    fn unit_or_one(&self, spec: &Toml, what: &str, ty: Ty) -> Result<Unit> {
        unit_of(spec, what, if ty == Ty::Bool { Some("1") } else { None })
    }
}

/// Stage S7.1: a mod, as its `mod.toml` describes it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModInfo {
    pub id: String,
    pub name: String,
    pub version: String,
    pub description: String,
    /// The id of the model the mod is for, if it names one.
    pub model: Option<String>,
    /// The mod's folder.
    pub dir: PathBuf,
}

/// Stage S7.1: reads a mod folder's `mod.toml`.
pub fn read_mod(dir: &Path) -> Result<(ModInfo, Vec<String>, Vec<u8>)> {
    let file = dir.join("mod.toml");
    let bytes = std::fs::read(&file).map_err(|e| Error::Model(format!("cannot read {}: {e}", file.display())))?;
    let text = std::str::from_utf8(&bytes).map_err(|_| Error::Model(format!("{} is not UTF-8", file.display())))?;
    let doc = text.parse::<Toml>().map_err(|e| Error::Model(format!("{}: {e}", file.display())))?;
    let Some(Value::Table(head)) = doc.get("mod") else {
        return model_err(format!("{}: needs a [mod] table", file.display()));
    };
    if doc.len() != 1 {
        return model_err(format!("{}: only [mod] belongs here; elements go in the mod's files", file.display()));
    }
    let id = text_of(head, "id").unwrap_or_default().to_string();
    let usable = id.chars().next().is_some_and(|c| c.is_ascii_lowercase())
        && id.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
        && !id.ends_with('_');
    if !usable {
        return model_err(format!(
            "{}: [mod] id must be a name of lower-case letters, digits and underscores",
            file.display()
        ));
    }
    let files = match head.get("files") {
        Some(Value::Array(list)) => list
            .iter()
            .map(|f| f.as_str().map(str::to_string))
            .collect::<Option<Vec<_>>>()
            .ok_or_else(|| Error::Model(format!("mod {id}: files must be a list of file names")))?,
        None => Vec::new(),
        _ => return model_err(format!("mod {id}: files must be a list of file names")),
    };
    let info = ModInfo {
        name: text_of(head, "name").unwrap_or(&id).to_string(),
        version: text_of(head, "version").unwrap_or("").to_string(),
        description: text_of(head, "description").unwrap_or("").to_string(),
        model: text_of(head, "model").map(str::to_string),
        dir: dir.to_path_buf(),
        id,
    };
    Ok((info, files, bytes))
}

/// The sections a mod's files may add to, besides `[patch]`.
const MOD_SECTIONS: [&str; 10] =
    ["dim", "param", "lever", "var", "state", "flow", "account", "renamed", "situation", "dilemma"];
/// The kinds of element a `[patch.<kind>.<name>]` may change.
const PATCH_KINDS: [&str; 6] = ["param", "lever", "var", "state", "flow", "account"];

/// Loads a model from a folder containing `model.toml`, or from the manifest itself.
pub fn load_model(path: &Path) -> Result<Model> {
    load_model_with_mods(path, &[])
}

/// Stage S7.1: loads a model with mods applied in order (each a folder with `mod.toml`).
pub fn load_model_with_mods(path: &Path, mod_dirs: &[PathBuf]) -> Result<Model> {
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
                if index > 1 && merged[index].contains_key(&key) {
                    return model_err(format!("{name}.{key} is declared twice"));
                }
                merged[index].insert(key, spec);
            }
        }
    }

    // ---- stage S7.1: mods, in order. Each adds elements named after it and patches others.
    let model_id = merged[0].get("id").and_then(Value::as_str).unwrap_or_default().to_string();
    let mut mods: Vec<ModInfo> = Vec::new();
    let mut mod_notes = Vec::new();
    let mut patched_by: HashMap<(String, String), String> = HashMap::new();
    for dir in mod_dirs {
        let (info, files, bytes) = read_mod(dir)?;
        let id = info.id.clone();
        if mods.iter().any(|m| m.id == id) {
            return model_err(format!("mod {id} is listed twice"));
        }
        if info.model.as_ref().is_some_and(|m| *m != model_id) {
            return model_err(format!(
                "mod {id} is for the model {:?}, not {model_id:?}",
                info.model.as_deref().unwrap()
            ));
        }
        digest.update(format!("mod:{id}/mod.toml").as_bytes());
        digest.update([0u8]);
        digest.update(&bytes);
        digest.update([0u8]);
        let prefix = format!("{id}_");
        let mut patches: Vec<(String, String, Toml)> = Vec::new();
        for file in &files {
            let path = dir.join(file);
            let bytes =
                std::fs::read(&path).map_err(|e| Error::Model(format!("cannot read {}: {e}", path.display())))?;
            let what = format!("mod {id}, {}", relative_name(file));
            digest.update(format!("mod:{id}/{}", relative_name(file)).as_bytes());
            digest.update([0u8]);
            digest.update(&bytes);
            digest.update([0u8]);
            let text = std::str::from_utf8(&bytes).map_err(|_| Error::Model(format!("{what} is not UTF-8")))?;
            let doc = text.parse::<Toml>().map_err(|e| Error::Model(format!("{what}: {e}")))?;
            for (name, content) in doc {
                let Value::Table(content) = content else {
                    return model_err(format!("{what}: [{name}] must be a table"));
                };
                if name == "patch" {
                    for (kind, elements) in content {
                        if !PATCH_KINDS.contains(&kind.as_str()) {
                            return model_err(format!(
                                "{what}: [patch.{kind}] is not a kind of element a mod can patch"
                            ));
                        }
                        let Value::Table(elements) = elements else {
                            return model_err(format!("{what}: [patch.{kind}] must be a table"));
                        };
                        for (element, spec) in elements {
                            let Value::Table(spec) = spec else {
                                return model_err(format!("{what}: patch.{kind}.{element} must be a table"));
                            };
                            patches.push((kind.clone(), element, spec));
                        }
                    }
                    continue;
                }
                if !MOD_SECTIONS.contains(&name.as_str()) {
                    return model_err(format!("{what}: a mod cannot add to [{name}]"));
                }
                let index = section(&name);
                for (key, spec) in content {
                    if !key.starts_with(&prefix) {
                        return model_err(format!("{what}: {name}.{key}: a mod's names start with {prefix:?}"));
                    }
                    if name != "renamed" && uses_data(&spec) {
                        return model_err(format!("{what}: {name}.{key}: mods cannot bring data files yet"));
                    }
                    if merged[index].contains_key(&key) {
                        return model_err(format!("{what}: {name}.{key} is declared twice"));
                    }
                    merged[index].insert(key, spec);
                }
            }
        }
        for (kind, element, spec) in patches {
            let what = format!("mod {id}: patch.{kind}.{element}");
            let index = section(&kind);
            let Some(Value::Table(target)) = merged[index].get_mut(&element) else {
                return model_err(format!("{what}: the model has no {kind} {element}"));
            };
            if uses_data(&Value::Table(spec.clone())) {
                return model_err(format!("{what}: mods cannot bring data files yet"));
            }
            for (key, value) in spec {
                let value = match (&value, target.get(&key)) {
                    (Value::String(new), Some(Value::String(old))) if new.contains("{base}") => {
                        let base = if key == "expr" || key == "next" { format!("({old})") } else { old.clone() };
                        Value::String(new.replace("{base}", &base))
                    }
                    (Value::String(new), _) if new.contains("{base}") => {
                        return model_err(format!("{what}: {key} has no earlier text for {{base}}"));
                    }
                    _ => value,
                };
                target.insert(key, value);
            }
            if let Some(earlier) = patched_by.insert((kind.clone(), element.clone()), id.clone()) {
                if earlier != id {
                    mod_notes.push(format!("{kind} {element} is patched by both {earlier} and {id}; {id} comes later"));
                }
            }
        }
        mods.push(info);
    }

    // ---- stage S7.3: each situation is a true/false state that turns on and off.
    let situations = std::mem::take(&mut merged[section("situation")]);
    let last_phase = match merged[0].get("phases") {
        Some(Value::Array(phases)) => phases.last().and_then(Value::as_str).unwrap_or_default().to_string(),
        _ => String::new(),
    };
    for (name, spec) in situations {
        let what = format!("situation {name}");
        let Value::Table(spec) = spec else { return model_err(format!("{what} must be a table")) };
        if let Some(key) =
            spec.keys().find(|k| !["label", "doc", "start", "end", "good", "phase"].contains(&k.as_str()))
        {
            return model_err(format!("{what}: unknown key {key:?}"));
        }
        let Some(start) = text_of(&spec, "start") else {
            return model_err(format!("{what}: needs 'start', the formula that turns it on"));
        };
        let next = match spec.get("end") {
            None => start.to_string(),
            Some(Value::String(end)) => format!("select({name}, not ({end}), {start})"),
            Some(_) => return model_err(format!("{what}: 'end' must be a formula")),
        };
        let good = match spec.get("good") {
            None => false,
            Some(Value::Boolean(good)) => *good,
            Some(_) => return model_err(format!("{what}: 'good' must be true or false")),
        };
        if merged[section("state")].contains_key(&name) {
            return model_err(format!("state.{name} is declared twice"));
        }
        let mut state = Toml::new();
        for key in ["label", "doc"] {
            if let Some(v) = spec.get(key) {
                state.insert(key.to_string(), v.clone());
            }
        }
        state.insert("type".to_string(), Value::String("bool".to_string()));
        state.insert("unit".to_string(), Value::String("1".to_string()));
        let phase = spec.get("phase").cloned().unwrap_or(Value::String(last_phase.clone()));
        state.insert("phase".to_string(), phase);
        state.insert("initial".to_string(), Value::Boolean(false));
        state.insert("next".to_string(), Value::String(next));
        state.insert("situation".to_string(), Value::String(if good { "good" } else { "bad" }.to_string()));
        merged[section("state")].insert(name, Value::Table(state));
    }
    let dilemmas = expand_dilemmas(&mut merged)?;

    let head = &merged[0];
    let format = match head.get("format").and_then(Value::as_integer) {
        Some(f @ (0 | 1)) => f,
        _ => return model_err("this loader reads model formats 0 and 1"),
    };
    if format == 0 && !merged[section("dim")].is_empty() {
        return model_err("dimensions need format = 1");
    }
    let mut dims: Vec<Dim> = Vec::new();
    let mut dim_index: HashMap<String, usize> = HashMap::new();
    for (name, spec) in &merged[section("dim")] {
        let what = format!("dim {name}");
        let spec = table_of(spec, &what)?;
        let usable = |n: &str| {
            let mut chars = n.chars();
            chars.next().is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
                && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
                && !FUNCTIONS.contains(&n)
                && !KEYWORDS.contains(&n)
        };
        if !usable(name) {
            return model_err(format!("{what}: not a usable name"));
        }
        let (first, members) = match (spec.get("range"), spec.get("members")) {
            (Some(Value::Array(range)), None) => {
                let ends: Vec<i64> = range.iter().filter_map(Value::as_integer).collect();
                match ends.as_slice() {
                    [lo, hi] if range.len() == 2 && lo <= hi => {
                        if hi - lo >= 1_000_000 {
                            return model_err(format!("{what}: more than 1,000,000 members"));
                        }
                        (Some(*lo), (*lo..=*hi).map(|v| v.to_string()).collect::<Vec<_>>())
                    }
                    _ => {
                        return model_err(format!(
                            "{what}: 'range' must be [first, last], whole numbers, first <= last"
                        ));
                    }
                }
            }
            (None, Some(Value::Array(list))) => {
                let names: Vec<String> = list.iter().filter_map(|v| v.as_str().map(str::to_string)).collect();
                if names.is_empty() || names.len() != list.len() || !names.iter().all(|n| usable(n)) {
                    return model_err(format!("{what}: members must be usable names"));
                }
                if (1..names.len()).any(|i| names[..i].contains(&names[i])) {
                    return model_err(format!("{what}: a member is listed twice"));
                }
                if names.len() > 1_000_000 {
                    return model_err(format!("{what}: more than 1,000,000 members"));
                }
                (None, names)
            }
            _ => return model_err(format!("{what}: give either 'range' or 'members'")),
        };
        let labels: Vec<String> = match spec.get("labels") {
            Some(Value::Array(l)) => {
                l.iter().map(|v| v.as_str().map(str::to_string).unwrap_or_else(|| v.to_string_lossy())).collect()
            }
            _ => members.clone(),
        };
        if labels.len() != members.len() {
            return model_err(format!("{what}: one label per member"));
        }
        dim_index.insert(name.clone(), dims.len());
        dims.push(Dim { name: name.clone(), first, members, labels });
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
    let mut loader = Loader {
        minor,
        format,
        root: root.clone(),
        dims,
        dim_index,
        cell_files: BTreeMap::new(),
        phases: phases.clone(),
        symbols: Vec::new(),
        sym_index: HashMap::new(),
        taken,
        entity_index: entity_index.clone(),
    };

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
                name: name.clone(),
                kind: Kind::Column,
                ty,
                unit,
                money,
                entity: Some(entity),
                phase: None,
                expr: None,
                initial: None,
                range: None,
                spec: spec.clone(),
                dims: Vec::new(),
                data: Vec::new(),
                rake: None,
            })?;
        }
    }

    for (name, spec) in &merged[section("param")] {
        let what = format!("param {name}");
        let spec = table_of(spec, &what)?;
        let (ty, money) = type_of(spec, &what)?;
        let unit = loader.unit_or_one(spec, &what, ty)?;
        let dims = loader.dims_of(spec, Kind::Param, &what)?;
        let data = loader.data_for(Kind::Param, &dims, spec, None, &what)?;
        loader.declare(Decl {
            name: name.clone(),
            kind: Kind::Param,
            ty,
            unit,
            money,
            entity: None,
            phase: None,
            expr: None,
            initial: None,
            range: range_of(spec, money, loader.minor, &what)?,
            spec: spec.clone(),
            dims,
            data,
            rake: None,
        })?;
    }

    for (name, spec) in &merged[section("lever")] {
        let what = format!("lever {name}");
        let spec = table_of(spec, &what)?;
        let (ty, money) = type_of(spec, &what)?;
        let Some(default) = spec.get("default") else { return model_err(format!("{what}: missing 'default'")) };
        loader.dims_of(spec, Kind::Lever, &what)?;
        let unit = loader.unit_or_one(spec, &what, ty)?;
        loader.declare(Decl {
            name: name.clone(),
            kind: Kind::Lever,
            ty,
            unit,
            money,
            entity: None,
            phase: None,
            expr: None,
            initial: Some(default.clone()),
            range: range_of(spec, money, loader.minor, &what)?,
            spec: spec.clone(),
            dims: Vec::new(),
            data: Vec::new(),
            rake: None,
        })?;
    }

    for (name, spec) in &merged[section("var")] {
        let what = format!("var {name}");
        let spec = table_of(spec, &what)?;
        let (ty, money) = type_of(spec, &what)?;
        let Some(expr) = spec.get("expr") else { return model_err(format!("{what}: missing 'expr'")) };
        let unit = loader.unit_or_one(spec, &what, ty)?;
        let dims = loader.dims_of(spec, Kind::Var, &what)?;
        let data = loader.data_for(Kind::Var, &dims, spec, spec.get("initial"), &what)?;
        loader.declare(Decl {
            name: name.clone(),
            kind: Kind::Var,
            ty,
            unit,
            money,
            entity: loader.entity_of(spec, &what)?,
            phase: loader.phase_of(spec, &what)?,
            expr: Some(formula_text(expr)),
            initial: spec.get("initial").cloned(),
            range: range_of(spec, money, loader.minor, &what)?,
            spec: spec.clone(),
            dims,
            data,
            rake: None,
        })?;
    }

    for (name, spec) in &merged[section("state")] {
        let what = format!("state {name}");
        let spec = table_of(spec, &what)?;
        let (ty, money) = type_of(spec, &what)?;
        let (Some(initial), true) = (spec.get("initial"), spec.contains_key("next") != spec.contains_key("rake"))
        else {
            return model_err(format!("{what}: needs 'initial' and either 'next' or 'rake'"));
        };
        let rake = match spec.get("rake") {
            Some(r) => Some(rake_of(r, &what)?),
            None => None,
        };
        let unit = loader.unit_or_one(spec, &what, ty)?;
        let dims = loader.dims_of(spec, Kind::State, &what)?;
        let data = loader.data_for(Kind::State, &dims, spec, Some(initial), &what)?;
        loader.declare(Decl {
            name: name.clone(),
            kind: Kind::State,
            ty,
            unit,
            money,
            entity: loader.entity_of(spec, &what)?,
            phase: loader.phase_of(spec, &what)?,
            expr: spec.get("next").map(formula_text),
            initial: Some(initial.clone()),
            range: range_of(spec, money, loader.minor, &what)?,
            spec: spec.clone(),
            dims,
            data,
            rake,
        })?;
    }

    let instrument_index = |name: &str| raw_instruments.iter().position(|i| i.name == name);
    let mut accounts: Vec<Account> = Vec::new();
    for (name, spec) in &merged[section("account")] {
        let what = format!("account {name}");
        let spec = table_of(spec, &what)?;
        loader.dims_of(spec, Kind::Account, &what)?;
        let (Some(sector), Some(instrument)) =
            (text_of(spec, "sector").and_then(sector_index), text_of(spec, "instrument").and_then(instrument_index))
        else {
            return model_err(format!("{what}: needs a declared 'sector' and 'instrument'"));
        };
        if accounts.iter().any(|a| a.sector == sector && a.instrument == instrument) {
            return model_err(format!(
                "{what}: sector {} already has an account in {}",
                sector_names[sector], raw_instruments[instrument].name
            ));
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
            name: name.clone(),
            kind: Kind::Account,
            ty: Ty::Int,
            unit,
            money: true,
            entity,
            phase: None,
            expr: None,
            initial: spec.get("initial").cloned(),
            range: range_of(spec, true, loader.minor, &what)?,
            spec: spec.clone(),
            dims: Vec::new(),
            data: Vec::new(),
            rake: None,
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
        loader.dims_of(spec, Kind::Flow, &what)?;
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
            (Some(_), Some(_)) => {
                return model_err(format!("{what}: flows between two per-record sectors are not in format 0"));
            }
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
            name: name.clone(),
            kind: Kind::Flow,
            ty: Ty::Int,
            unit,
            money: true,
            entity,
            phase: loader.phase_of(spec, &what)?,
            expr: Some(formula_text(expr)),
            initial: spec.get("initial").cloned(),
            range: range_of(spec, true, loader.minor, &what)?,
            spec: spec.clone(),
            dims: Vec::new(),
            data: Vec::new(),
            rake: None,
        })?;
        flows.push(Flow { sym, src_account, dst_account });
    }

    let mut instruments = Vec::new();
    for (index, raw) in raw_instruments.iter().enumerate() {
        let Some(issuer_account) = account_of(&accounts, raw.issuer, index) else {
            return model_err(format!(
                "instrument {}: the issuer {} needs an account",
                raw.name, sector_names[raw.issuer]
            ));
        };
        if sectors[raw.issuer].entity.is_some() {
            return model_err(format!("instrument {}: the issuer cannot be a per-record sector", raw.name));
        }
        instruments.push(Instrument {
            name: raw.name.clone(),
            unit: raw.unit.clone(),
            issuer: raw.issuer,
            issuer_account,
        });
    }

    check_weights(&entities, &sectors, &loader, &phases)?;
    let legislature = check_legislature(&merged[section("legislature")], &loader, format)?;
    let renamed = check_renamed(&merged[section("renamed")], &loader)?;

    for dim in &loader.dims {
        if dim.first.is_none() {
            if let Some(member) = dim.members.iter().find(|m| loader.sym_index.contains_key(*m)) {
                return model_err(format!("dim {}: the member {member:?} has the name of an element", dim.name));
            }
        }
        if loader.sym_index.contains_key(&dim.name) {
            return model_err(format!("the name {:?} is used twice", dim.name));
        }
    }
    // Data files of dimensioned elements, after the entities', in ascending order of path.
    for (file, (_, bytes)) in &loader.cell_files {
        digest.update(relative_name(file).as_bytes());
        digest.update([0u8]);
        digest.update(bytes);
        digest.update([0u8]);
    }

    Ok(Model {
        root,
        mods,
        mod_notes,
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
        dims: loader.dims,
        dim_index: loader.dim_index,
        format,
        legislature,
        renamed,
        dilemmas,
    })
}

const DILEMMA_KEYS: [&str; 6] = ["label", "doc", "start", "again_after", "option", "phase"];
const OPTION_KEYS: [&str; 5] = ["name", "label", "doc", "months", "effect"];
/// What a dilemma makes besides its lever: (suffix, section).
const DILEMMA_PARTS: [(&str, &str); 6] = [
    ("", "lever"),
    ("_choice", "var"),
    ("_age", "var"),
    ("_answer", "state"),
    ("_months", "state"),
    ("_open", "state"),
];

/// `None` for a missing key, `Some(Some(n))` for a whole number of at least 1, `Some(None)`
/// for anything else.
fn whole_at_least_one(value: Option<&Value>) -> Option<Option<i64>> {
    match value {
        None => None,
        Some(Value::Integer(n)) if *n >= 1 => Some(Some(*n)),
        Some(_) => Some(None),
    }
}

fn is_option_name(name: &str) -> bool {
    let mut chars = name.chars();
    chars.next().is_some_and(|c| c.is_ascii_lowercase() || c == '_')
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
}

/// Stage S9.1: a var computing `formula`, an element's formula before a dilemma's effects:
/// of the element's type, unit, dimensions, entity and phase (a national flow's: money, its
/// instrument's unit a step). Mirrors the oracle's `_carrier`.
fn carrier(merged: &[Toml], kind: &str, element: &Toml, formula: &str, dilemma: &str, what: &str) -> Result<Toml> {
    let section = |name: &str| SECTIONS.iter().position(|s| *s == name).unwrap();
    let mut out = Toml::new();
    if kind == "flow" {
        for side in ["from", "to"] {
            let sector = element.get(side).and_then(Value::as_str).and_then(|s| merged[section("sector")].get(s));
            if sector.and_then(|s| s.get("entity")).is_some() {
                return model_err(format!("{what}: an effect on a flow held record by record is not supported"));
            }
        }
        let instruments = &merged[section("instrument")];
        let instrument =
            element.get("instrument").and_then(Value::as_str).or_else(|| instruments.keys().next().map(String::as_str));
        let unit = instrument
            .and_then(|i| instruments.get(i))
            .and_then(|i| i.get("unit"))
            .and_then(Value::as_str)
            .unwrap_or_default();
        let step = merged[0].get("step").and_then(Value::as_str).unwrap_or_default();
        out.insert("type".to_string(), Value::String("money".to_string()));
        out.insert("unit".to_string(), Value::String(format!("{unit}/{step}")));
    } else {
        for key in ["type", "unit", "dims", "entity"] {
            if let Some(v) = element.get(key) {
                out.insert(key.to_string(), v.clone());
            }
        }
    }
    if let Some(phase) = element.get("phase") {
        out.insert("phase".to_string(), phase.clone());
    }
    out.insert("expr".to_string(), Value::String(formula.to_string()));
    out.insert("dilemma".to_string(), Value::String(dilemma.to_string()));
    Ok(out)
}

/// Stage S9.1: each dilemma becomes a lever for the answer given this month, vars for the
/// answer in force and its age, and states for the answer, the months since and whether the
/// dilemma is open; each answer's effects then wrap the formulas they name. Mirrors the
/// oracle's `_expand_dilemmas`.
fn expand_dilemmas(merged: &mut [Toml]) -> Result<Vec<DilemmaInfo>> {
    let section = |name: &str| SECTIONS.iter().position(|s| *s == name).unwrap();
    let (first_phase, last_phase) = match merged[0].get("phases") {
        Some(Value::Array(phases)) if !phases.is_empty() && phases.iter().all(Value::is_str) => {
            (phases[0].as_str().unwrap().to_string(), phases[phases.len() - 1].as_str().unwrap().to_string())
        }
        _ => (String::new(), String::new()),
    };
    let dilemmas = std::mem::take(&mut merged[section("dilemma")]);
    let mut made: HashSet<String> = HashSet::new();
    // A dilemma that passed the checks.
    struct Checked {
        name: String,
        spec: Toml,
        start: String,
        again: Option<i64>,
        options: Vec<Toml>,
    }
    let mut checked: Vec<Checked> = Vec::new();
    for (name, spec) in dilemmas {
        let what = format!("dilemma {name}");
        let Value::Table(spec) = spec else { return model_err(format!("{what} must be a table")) };
        if let Some(key) = spec.keys().find(|k| !DILEMMA_KEYS.contains(&k.as_str())) {
            return model_err(format!("{what}: unknown key {key:?}"));
        }
        let Some(start) = text_of(&spec, "start") else {
            return model_err(format!("{what}: needs 'start', the formula that opens it"));
        };
        let start = start.to_string();
        let again = match whole_at_least_one(spec.get("again_after")) {
            None => None,
            Some(Some(n)) => Some(n),
            Some(None) => {
                return model_err(format!("{what}: 'again_after' must be a whole number of months, at least 1"));
            }
        };
        let options: Vec<Toml> = match spec.get("option") {
            Some(Value::Array(list)) if (2..=6).contains(&list.len()) && list.iter().all(Value::is_table) => {
                list.iter().map(|o| o.as_table().unwrap().clone()).collect()
            }
            _ => {
                return model_err(format!("{what}: needs two to six answers, each an [[dilemma.{name}.option]] table"));
            }
        };
        let mut seen: HashSet<String> = HashSet::new();
        for option in &options {
            if let Some(key) = option.keys().find(|k| !OPTION_KEYS.contains(&k.as_str())) {
                return model_err(format!("{what}: an answer has the unknown key {key:?}"));
            }
            let Some(answer) = text_of(option, "name").filter(|n| is_option_name(n)) else {
                return model_err(format!("{what}: each answer needs a 'name', a lowercase identifier"));
            };
            if !seen.insert(answer.to_string()) {
                return model_err(format!("{what}: the answer {answer:?} is given twice"));
            }
            if let Some(None) = whole_at_least_one(option.get("months")) {
                return model_err(format!("{what}, answer {answer}: 'months' must be a whole number, at least 1"));
            }
            match option.get("effect") {
                None => {}
                Some(Value::Table(effect)) if effect.values().all(Value::is_str) => {}
                Some(_) => return model_err(format!("{what}, answer {answer}: 'effect' must be a table of formulas")),
            }
        }
        for (suffix, kind) in DILEMMA_PARTS {
            let part = format!("{name}{suffix}");
            if merged[section(kind)].contains_key(&part) || made.contains(&part) {
                return model_err(format!("{kind}.{part} is declared twice"));
            }
            made.insert(part);
        }
        checked.push(Checked { name, spec, start, again, options });
    }

    let mut out = Vec::new();
    for Checked { name, spec, start, again, options } in &checked {
        let text = |key: &str| text_of(spec, key).map(str::to_string);
        let mut lever = Toml::new();
        for key in ["label", "doc"] {
            if let Some(v) = spec.get(key) {
                lever.insert(key.to_string(), v.clone());
            }
        }
        let int = |phase: &str| {
            let mut t = Toml::new();
            t.insert("type".to_string(), Value::String("int".to_string()));
            t.insert("unit".to_string(), Value::String("1".to_string()));
            t.insert("phase".to_string(), Value::String(phase.to_string()));
            t.insert("dilemma".to_string(), Value::String(name.clone()));
            t
        };
        lever.insert("type".to_string(), Value::String("int".to_string()));
        lever.insert("unit".to_string(), Value::String("1".to_string()));
        lever.insert("default".to_string(), Value::Integer(0));
        lever.insert("range".to_string(), Value::Array(vec![Value::Integer(0), Value::Integer(options.len() as i64)]));
        lever.insert("dilemma".to_string(), Value::String(name.clone()));
        merged[section("lever")].insert(name.clone(), Value::Table(lever));
        let mut choice = int(&first_phase);
        choice.insert("expr".to_string(), Value::String(format!("select({name} != 0, {name}, {name}_answer)")));
        merged[section("var")].insert(format!("{name}_choice"), Value::Table(choice));
        let mut age = int(&first_phase);
        age.insert("expr".to_string(), Value::String(format!("select({name} != 0, 0, {name}_months)")));
        merged[section("var")].insert(format!("{name}_age"), Value::Table(age));
        let phase = spec.get("phase").cloned().unwrap_or(Value::String(last_phase.clone()));
        let state = |next: String| {
            let mut t = int("");
            t.insert("phase".to_string(), phase.clone());
            t.insert("initial".to_string(), Value::Integer(0));
            t.insert("next".to_string(), Value::String(next));
            t
        };
        merged[section("state")].insert(format!("{name}_answer"), Value::Table(state(format!("{name}_choice"))));
        merged[section("state")].insert(format!("{name}_months"), Value::Table(state(format!("{name}_age + 1"))));
        let fresh = match again {
            None => format!("{name}_choice == 0"),
            Some(a) => format!("({name}_choice == 0 or {name}_age + 1 >= {a})"),
        };
        let mut open = Toml::new();
        open.insert("type".to_string(), Value::String("bool".to_string()));
        open.insert("unit".to_string(), Value::String("1".to_string()));
        open.insert("phase".to_string(), phase.clone());
        open.insert("initial".to_string(), Value::Boolean(false));
        open.insert("dilemma".to_string(), Value::String(name.clone()));
        open.insert(
            "next".to_string(),
            Value::String(format!("select({name}_open, {name} == 0, ({start}) and {fresh})")),
        );
        merged[section("state")].insert(format!("{name}_open"), Value::Table(open));
        out.push(DilemmaInfo {
            name: name.clone(),
            label: text("label").unwrap_or_else(|| name.clone()),
            doc: text("doc").unwrap_or_default(),
            again_after: *again,
            options: options
                .iter()
                .map(|o| {
                    let answer = text_of(o, "name").unwrap().to_string();
                    DilemmaOption {
                        label: text_of(o, "label").map(str::to_string).unwrap_or_else(|| answer.clone()),
                        doc: text_of(o, "doc").unwrap_or_default().to_string(),
                        months: o.get("months").and_then(Value::as_integer),
                        name: answer,
                    }
                })
                .collect(),
        });
    }

    for Checked { name, options, .. } in &checked {
        // Each element this dilemma's answers change, in order of first mention, with the
        // answers' effects in order: (what, when, formula).
        type Effects = Vec<(String, String, String)>;
        let mut per_target: Vec<(String, Effects)> = Vec::new();
        for (k, option) in options.iter().enumerate() {
            let k = k + 1;
            let what = format!("dilemma {name}, answer {}", text_of(option, "name").unwrap());
            let when = match option.get("months").and_then(Value::as_integer) {
                None => format!("{name}_choice == {k}"),
                Some(m) => format!("{name}_choice == {k} and {name}_age < {m}"),
            };
            let Some(Value::Table(effect)) = option.get("effect") else { continue };
            for (target, formula) in effect {
                let entry = (what.clone(), when.clone(), formula.as_str().unwrap().to_string());
                match per_target.iter_mut().find(|(t, _)| t == target) {
                    Some((_, effects)) => effects.push(entry),
                    None => per_target.push((target.clone(), vec![entry])),
                }
            }
        }
        for (target, effects) in per_target {
            let what = &effects[0].0;
            let mut found = None;
            if !made.contains(&target) {
                for (kind, key) in [("var", "expr"), ("flow", "expr"), ("state", "next")] {
                    if matches!(merged[section(kind)].get(&target), Some(Value::Table(_))) {
                        found = Some((kind, key));
                        break;
                    }
                }
            }
            let Some((kind, key)) = found else {
                return model_err(format!("{what}: the model has no var, flow or state {target} of its own"));
            };
            let Some(Value::Table(element)) = merged[section(kind)].get(&target).cloned() else { unreachable!() };
            let Some(old) = element.get(key).and_then(Value::as_str).map(str::to_string) else {
                return model_err(format!("{what}: {target} has no formula to change"));
            };
            // The formula so far goes into a var of its own, which each answer's effect reads
            // once, so formulas grow by the effects, not by doubling.
            let before = format!("{target}_before_{name}");
            if merged[section("var")].contains_key(&before) || made.contains(&before) {
                return model_err(format!("var.{before} is declared twice"));
            }
            made.insert(before.clone());
            let carrier = carrier(merged, kind, &element, &old, name, what)?;
            merged[section("var")].insert(before.clone(), Value::Table(carrier));
            let mut body = before.clone();
            for (_, when, formula) in effects.iter().rev() {
                body = format!("select({when}, ({}), ({body}))", formula.replace("{base}", &before));
            }
            let Some(Value::Table(element)) = merged[section(kind)].get_mut(&target) else { unreachable!() };
            element.insert(key.to_string(), Value::String(body));
        }
    }
    Ok(out)
}

/// Stage S7.0: `[renamed] old = "new"`. An old name is no longer a name in the model; the
/// new one is an element, or itself renamed again (the chain is followed to an element).
fn check_renamed(spec: &Toml, loader: &Loader) -> Result<Vec<(String, String)>> {
    let mut step: HashMap<&str, &str> = HashMap::new();
    for (old, new) in spec {
        let Some(new) = new.as_str() else {
            return model_err(format!("renamed.{old}: must be the element's new name, as text"));
        };
        if loader.sym_index.contains_key(old) || loader.dim_index.contains_key(old) {
            return model_err(format!("renamed.{old}: {old:?} is still a name in the model"));
        }
        step.insert(old.as_str(), new);
    }
    let mut out = Vec::new();
    for (&old, &first) in &step {
        let mut name = first;
        let mut seen = vec![old];
        while !loader.sym_index.contains_key(name) {
            let Some(&next) = step.get(name) else {
                return model_err(format!("renamed.{old}: {name:?} is not an element of the model"));
            };
            if seen.contains(&name) {
                return model_err(format!("renamed.{old}: the renames go round in a circle"));
            }
            seen.push(name);
            name = next;
        }
        out.push((old.to_string(), name.to_string()));
    }
    out.sort();
    Ok(out)
}

/// Format 1 (S4.4): the structure of a rake; names and formulas are checked later.
fn rake_of(value: &Value, what: &str) -> Result<Rake> {
    let what = format!("{what} rake");
    let Value::Table(spec) = value else { return model_err(format!("{what}: takes 'when', 'passes' and 'margin'")) };
    if spec.keys().any(|k| !matches!(k.as_str(), "when" | "passes" | "margin")) {
        return model_err(format!("{what}: takes 'when', 'passes' and 'margin'"));
    }
    let passes = match spec.get("passes") {
        Some(Value::Integer(n)) if (1..=1000).contains(n) => *n as u32,
        _ => return model_err(format!("{what}: 'passes' must be a whole number from 1 to 1,000")),
    };
    let Some(Value::String(when)) = spec.get("when") else {
        return model_err(format!("{what}: 'when' must be a formula"));
    };
    let margins = match spec.get("margin") {
        Some(Value::Array(list)) if !list.is_empty() => list,
        _ => return model_err(format!("{what}: needs at least one margin")),
    };
    let mut out = Vec::new();
    for (k, margin) in margins.iter().enumerate() {
        let where_ = format!("{what} margin {}", k + 1);
        let (Some(Value::Table(m)), true) = (Some(margin), true) else {
            return model_err(format!("{where_}: needs 'target' and 'slots'"));
        };
        let (Some(Value::String(target)), Some(slots), 2) = (m.get("target"), m.get("slots"), m.len()) else {
            return model_err(format!("{where_}: needs 'target' and 'slots'"));
        };
        let Value::Array(slots) = slots else { return model_err(format!("{where_}: needs at least one slot")) };
        if slots.is_empty() {
            return model_err(format!("{where_}: needs at least one slot"));
        }
        let mut parsed = Vec::new();
        for slot in slots {
            let bad = || model_err(format!("{where_}: a slot needs 'count' (a formula) and 'at' (a list of formulas)"));
            let Value::Table(slot) = slot else { return bad() };
            let (Some(Value::String(count)), Some(Value::Array(at)), 2) =
                (slot.get("count"), slot.get("at"), slot.len())
            else {
                return bad();
            };
            let Some(at) = at.iter().map(|a| a.as_str().map(str::to_string)).collect::<Option<Vec<String>>>() else {
                return bad();
            };
            parsed.push(Slot { count: count.clone(), at });
        }
        out.push(Margin { target: target.clone(), slots: parsed });
    }
    Ok(Rake { when: when.clone(), passes, margins: out })
}

/// Format 1 (S5.4): the legislature that votes on lever changes, and levers' leanings.
fn check_legislature(spec: &Toml, loader: &Loader, format: i64) -> Result<Option<Legislature>> {
    for d in loader.symbols.iter().filter(|d| d.kind == Kind::Lever) {
        if let Some(leaning) = d.spec.get("leaning") {
            if !matches!(leaning.as_str(), Some("left" | "right")) {
                return model_err(format!("lever {}: 'leaning' is \"left\" or \"right\"", d.name));
            }
            if d.ty == Ty::Bool {
                return model_err(format!("lever {}: a true/false lever has no leaning", d.name));
            }
        }
    }
    if spec.is_empty() {
        return Ok(None);
    }
    if format != 1 {
        return model_err("[legislature] needs format = 1");
    }
    let keys_ok =
        spec.len() == 3 && ["seats", "governing", "position"].iter().all(|k| spec.get(*k).is_some_and(Value::is_str));
    if !keys_ok {
        return model_err("[legislature] takes 'seats', 'governing' and 'position', each a name");
    }
    let mut ids = [0usize; 3];
    let mut dims: Option<&Vec<usize>> = None;
    for (slot, (key, kind, ty)) in
        [("seats", Kind::State, Ty::Int), ("governing", Kind::State, Ty::Bool), ("position", Kind::Param, Ty::Real)]
            .into_iter()
            .enumerate()
    {
        let name = spec[key].as_str().expect("checked above");
        let id = match loader.sym_index.get(name) {
            Some(&id) => id,
            None => usize::MAX,
        };
        let d = loader.symbols.get(id);
        let Some(d) = d.filter(|d| d.kind == kind && d.ty == ty && !d.money && d.dims.len() == 1) else {
            return model_err(format!(
                "[legislature] {key}: must be a {} of type {} with one dimension",
                kind.name(),
                ty.name()
            ));
        };
        if dims.is_some_and(|x| *x != d.dims) {
            return model_err("[legislature]: seats, governing and position must have the same dimension");
        }
        dims = Some(&d.dims);
        ids[slot] = id;
    }
    Ok(Some(Legislature { seats: ids[0], governing: ids[1], position: ids[2] }))
}

/// Format 1 (S4.4): weight states and rakes.
fn check_weights(entities: &[Entity], sectors: &[Sector], loader: &Loader, phases: &[String]) -> Result<()> {
    let sym = |name: &str| loader.sym_index.get(name).map(|i| &loader.symbols[*i]);
    for (index, entity) in entities.iter().enumerate() {
        let Some(state) = &entity.weight_state else { continue };
        let what = format!("entity {}: the weight state {state:?}", entity.name);
        let d = match sym(state) {
            Some(d) if d.kind == Kind::State && d.entity == Some(index) => d,
            _ => return model_err(format!("{what} must be a state of that entity")),
        };
        if d.ty != Ty::Int || d.money || d.unit != Unit::one() || !d.dims.is_empty() {
            return model_err(format!("{what} must be of type int and unit 1"));
        }
        if let Some(sector) = sectors.iter().find(|s| s.entity == Some(index)) {
            return model_err(format!(
                "sector {}: its accounts are held in {}, whose weights change",
                sector.name, entity.name
            ));
        }
    }
    for d in &loader.symbols {
        let Some(rake) = &d.rake else { continue };
        let what = format!("state {} rake", d.name);
        if !entities.iter().any(|e| e.weight_state.as_deref() == Some(d.name.as_str())) {
            return model_err(format!("{what}: only a weight state can have a rake"));
        }
        for (k, margin) in rake.margins.iter().enumerate() {
            let where_ = format!("{what} margin {}", k + 1);
            let t = match sym(&margin.target) {
                Some(t)
                    if matches!(t.kind, Kind::Param | Kind::Var | Kind::State)
                        && !t.dims.is_empty()
                        && t.ty != Ty::Bool =>
                {
                    t
                }
                _ => return model_err(format!("{where_}: the target must be a param, var or state with dimensions")),
            };
            if let (Kind::Var, Some(tp), Some(dp)) = (t.kind, t.phase, d.phase) {
                if tp > dp {
                    return model_err(format!(
                        "{where_}: the target {} is computed in a later phase ({}) than the rake ({})",
                        t.name, phases[tp], phases[dp]
                    ));
                }
            }
            for slot in &margin.slots {
                if slot.at.len() != t.dims.len() {
                    let names: Vec<&str> = t.dims.iter().map(|x| loader.dims[*x].name.as_str()).collect();
                    return model_err(format!(
                        "{where_}: 'at' needs one formula per dimension of {} ({})",
                        t.name,
                        names.join(", ")
                    ));
                }
            }
        }
    }
    Ok(())
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
    /// Columns an interactive session shows after each step (`[play] watch`). Not part
    /// of the run: the oracle ignores it.
    pub watch: Vec<String>,
    /// The whole `[play]` table: presentation settings for a game client (country name,
    /// start date, which sector is the government). Not part of the run.
    pub play: Toml,
}

pub fn load_scenario(path: &Path) -> Result<Scenario> {
    load_scenario_with_mods(path, &[])
}

/// Stage S7.1: loads a scenario with further mods after its own (`[scenario] mods`), as a
/// game client does when the player chooses them.
pub fn load_scenario_with_mods(path: &Path, extra_mods: &[PathBuf]) -> Result<Scenario> {
    let text =
        std::fs::read_to_string(path).map_err(|e| Error::Model(format!("cannot read {}: {e}", path.display())))?;
    let doc = text.parse::<Toml>().map_err(|e| Error::Model(format!("{}: {e}", path.display())))?;
    let Some(Value::Table(head)) = doc.get("scenario") else {
        return model_err("scenario file needs a [scenario] table");
    };
    let (Some(model_path), Some(seed), Some(steps)) = (
        text_of(head, "model"),
        head.get("seed").and_then(Value::as_integer),
        head.get("steps").and_then(Value::as_integer),
    ) else {
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
            let (Some(step), Some(Value::Table(set))) = (item.get("step").and_then(Value::as_integer), item.get("set"))
            else {
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
    let mut mods: Vec<PathBuf> = match head.get("mods") {
        None => Vec::new(),
        Some(Value::Array(list)) => {
            list.iter()
                .map(|m| m.as_str().map(|m| base.join(m)))
                .collect::<Option<Vec<_>>>()
                .ok_or_else(|| Error::Model("[scenario] mods must be a list of folders".to_string()))?
        }
        Some(_) => return model_err("[scenario] mods must be a list of folders"),
    };
    mods.extend(extra_mods.iter().cloned());
    Ok(Scenario {
        name: path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default(),
        model: load_model_with_mods(&base.join(model_path), &mods)?,
        seed: seed as u64,
        steps: steps.max(0) as u64,
        preset: text_of(head, "preset").unwrap_or("central").to_string(),
        params: pairs("params"),
        levers: pairs("levers"),
        commands,
        watch: match doc.get("play").and_then(|p| p.get("watch")) {
            Some(Value::Array(items)) => items.iter().filter_map(|v| v.as_str().map(str::to_string)).collect(),
            _ => Vec::new(),
        },
        play: match doc.get("play") {
            Some(Value::Table(table)) => table.clone(),
            _ => Toml::new(),
        },
    })
}

#[cfg(test)]
mod tests {
    use super::exact_minor_units;

    #[test]
    fn money_is_scaled_from_the_number_as_typed() {
        // The same cases are in oracle/tests/test_language.py.
        let cases: [(f64, i64); 7] = [
            (2301745961.03, 230174596103),
            (0.29, 29),
            (1.1, 110),
            (-5072066666.6, -507206666660),
            (24217000000.0, 2421700000000),
            (1e16, 1_000_000_000_000_000_000),
            (12.5, 1250),
        ];
        for (raw, pence) in cases {
            assert_eq!(exact_minor_units(raw, 100), Some(pence), "{raw}");
        }
        assert_eq!(exact_minor_units(3.0, 1), Some(3));
        for raw in [1.005, 0.123456789, 2301745961.035, 1.5e-7] {
            assert_eq!(exact_minor_units(raw, 100), None, "{raw}");
        }
        assert_eq!(exact_minor_units(1.5, 1), None);
    }
}

#[cfg(test)]
mod money_tests {
    use super::{exact_minor_units, exact_minor_units_of_text};

    /// Stage S10: reading a plain decimal's digits gives what printing the float back gives.
    #[test]
    fn money_from_text_matches_money_from_the_float() {
        let mut texts: Vec<String> = [
            "0",
            "0.0",
            "-0.0",
            "1",
            "1.5",
            "1.50",
            "-2.25",
            "2301745961.03",
            "0.01",
            "0.001",
            "0.005",
            "123456789012.34",
            "999999999999999",
            "99999999999999.9",
            "0.1",
            "0.30",
            "+7.07",
            "00012.50",
            "1234567.891",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();
        // Many more: random decimals of up to 15 significant digits.
        let mut x: u64 = 0x9e37_79b9_7f4a_7c15;
        for _ in 0..20_000 {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            let digits = 1 + (x % 15) as usize;
            let point = (x >> 8) as usize % (digits + 1);
            let mut number: String = (0..digits).map(|k| char::from(b'0' + ((x >> (k * 4 % 60)) % 10) as u8)).collect();
            if point > 0 && point < digits {
                number.insert(point, '.');
            }
            if x & 1 == 1 {
                number.insert(0, '-');
            }
            texts.push(number);
        }
        for text in &texts {
            let f: f64 = text.parse().unwrap();
            for minor in [1, 100, 1000] {
                if let Some(fast) = exact_minor_units_of_text(text, minor) {
                    assert_eq!(fast, exact_minor_units(f, minor), "{text} in units of 1/{minor}");
                }
            }
        }
        assert_eq!(exact_minor_units_of_text("1e5", 100), None);
        assert_eq!(exact_minor_units_of_text("1234567890123456", 100), None);
        assert_eq!(exact_minor_units_of_text("5.", 100), None);
    }
}
