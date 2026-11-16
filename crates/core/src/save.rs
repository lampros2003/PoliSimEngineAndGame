//! Snapshot saves.
//!
//! A save holds everything needed to continue a run: the seed, the number of completed
//! steps, the resolved parameter values and the persistent state (the same values the
//! state hash covers). It names the model by hash and refuses to load into another one.
//! Loading then continuing gives exactly the run that was never interrupted.
//!
//! Layout, all integers little-endian:
//!
//! ```text
//! "PSIMSAVE"                      8 bytes
//! format                          u32, currently 1
//! engine version                  u16 length + UTF-8
//! model hash                      32 bytes
//! seed                            u64
//! steps completed                 u64
//! state hash at the time of save  32 bytes
//! parameter count                 u32
//!   name                          u16 length + UTF-8
//!   type                          u8: 0 whole number, 1 real, 2 true/false;
//!                                 3, 4, 5 the same for a dimensioned parameter (format 1)
//!   value                         8 bytes (1 byte for true/false); for types 3 to 5, a u64
//!                                 count then that many values, in row-major order
//! value count                     u32, the hashed symbols in hash order
//!   name                          u16 length + UTF-8
//!   type                          u8, as above
//!   shape                         u8: 0 one value, 1 one value per record
//!   count                         u64
//!   values                        count * 8 bytes (count bytes for true/false)
//! format 1 (stage S7.0), what each value is, so that a save can follow model changes:
//! dimension count                 u32
//!   name                          u16 length + UTF-8
//!   member count, members         u32, then each member as u16 length + UTF-8
//! entity count                    u32
//!   name                          u16 length + UTF-8
//!   record ids hash               32 bytes: SHA-256 of the ids as little-endian u64s
//! for each value, in order:
//!   kind                          u8: 0 var or flow, 1 lever, 2 account, 3 state
//!   entity                        u32 index into the entities, or u32::MAX for none
//!   dimension count, dimensions   u8, then each as a u32 index into the dimensions
//! ```
//!
//! A save loads into the model it was made with exactly ([`Simulation::resume`]). Into a
//! changed model, [`Simulation::migrate`] carries what still fits and reports the rest.

use std::collections::HashMap;
use std::sync::Arc;

use toml::Value;

use crate::error::{Error, Result};
use crate::model::Model;
use crate::program::{Col, Val};
use crate::sim::{Before, Computed, Params, Simulation, family, ids_hash};

const MAGIC: &[u8; 8] = b"PSIMSAVE";
const FORMAT: u32 = 1;

/// Stage S7.0: what loading a save into a changed model did.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Migration {
    /// Values carried from the save.
    pub carried: usize,
    /// Values new to the model, or changed in kind, shape or type, which start again from
    /// their initial value.
    pub reset: Vec<String>,
    /// Levers whose saved setting was outside their new range, moved to its nearer end.
    pub clamped: Vec<String>,
    /// Values in the save that the model no longer has.
    pub dropped: Vec<String>,
    /// Values carried under a new name: (name in the save, name now).
    pub renamed: Vec<(String, String)>,
}

/// A save file read but not yet applied.
struct Snapshot {
    format: u32,
    model_hash: [u8; 32],
    seed: u64,
    steps_done: u64,
    state_hash: [u8; 32],
    params: Vec<(String, Computed)>,
    values: Vec<(String, Computed)>,
    /// Format 1: per value, its kind family, entity and dimensions.
    shapes: Vec<Shape>,
}

struct Shape {
    family: u8,
    entity: Option<(String, [u8; 32])>,
    dims: Vec<(String, Vec<String>)>,
}

fn put_name(out: &mut Vec<u8>, name: &str) {
    out.extend_from_slice(&(name.len() as u16).to_le_bytes());
    out.extend_from_slice(name.as_bytes());
}

fn put_column(out: &mut Vec<u8>, column: &Col) {
    match column {
        Col::I(c) => c.iter().for_each(|v| out.extend_from_slice(&v.to_le_bytes())),
        Col::F(c) => c.iter().for_each(|v| out.extend_from_slice(&v.to_bits().to_le_bytes())),
        Col::B(c) => out.extend(c.iter().map(|v| *v as u8)),
    }
}

fn put_val(out: &mut Vec<u8>, value: &Val) {
    match value {
        Val::I(v) => out.extend_from_slice(&v.to_le_bytes()),
        Val::F(v) => out.extend_from_slice(&v.to_bits().to_le_bytes()),
        Val::B(v) => out.push(*v as u8),
    }
}

fn tag(value: &Val) -> u8 {
    match value {
        Val::I(_) => 0,
        Val::F(_) => 1,
        Val::B(_) => 2,
    }
}

struct Reader<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn take(&mut self, count: usize) -> Result<&'a [u8]> {
        let end = self.pos.checked_add(count).filter(|end| *end <= self.bytes.len());
        let Some(end) = end else { return Err(Error::Model("the save file is cut short".to_string())) };
        let slice = &self.bytes[self.pos..end];
        self.pos = end;
        Ok(slice)
    }

    fn u8(&mut self) -> Result<u8> {
        Ok(self.take(1)?[0])
    }

    fn u16(&mut self) -> Result<u16> {
        Ok(u16::from_le_bytes(self.take(2)?.try_into().expect("two bytes")))
    }

    fn u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().expect("four bytes")))
    }

    fn u64(&mut self) -> Result<u64> {
        Ok(u64::from_le_bytes(self.take(8)?.try_into().expect("eight bytes")))
    }

    fn hash(&mut self) -> Result<[u8; 32]> {
        Ok(self.take(32)?.try_into().expect("thirty-two bytes"))
    }

    fn name(&mut self) -> Result<String> {
        let length = self.u16()? as usize;
        let text = std::str::from_utf8(self.take(length)?).map_err(|_| corrupt())?;
        Ok(text.to_string())
    }

    /// `count` values of type `tag` (0 whole, 1 real, 2 true/false).
    fn column(&mut self, tag: u8, count: usize) -> Result<Col> {
        Ok(match tag {
            0 => Col::I((0..count).map(|_| self.u64().map(|v| v as i64)).collect::<Result<_>>()?),
            1 => Col::F((0..count).map(|_| self.u64().map(f64::from_bits)).collect::<Result<_>>()?),
            2 => Col::B(self.take(count)?.iter().map(|b| *b != 0).collect()),
            _ => return Err(corrupt()),
        })
    }

    fn val(&mut self, tag: u8) -> Result<Val> {
        match tag {
            0 => Ok(Val::I(self.u64()? as i64)),
            1 => Ok(Val::F(f64::from_bits(self.u64()?))),
            2 => Ok(Val::B(self.u8()? != 0)),
            _ => Err(corrupt()),
        }
    }
}

fn corrupt() -> Error {
    Error::Model("the save file is damaged".to_string())
}

impl Simulation {
    /// Serialises the run so that it can be continued later.
    pub fn save(&self) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend_from_slice(MAGIC);
        out.extend_from_slice(&FORMAT.to_le_bytes());
        put_name(&mut out, crate::VERSION);
        out.extend_from_slice(&self.model().model_hash);
        out.extend_from_slice(&self.seed().to_le_bytes());
        out.extend_from_slice(&self.steps_done().to_le_bytes());
        out.extend_from_slice(&self.state_hash());

        let params = self.params();
        out.extend_from_slice(&(params.len() as u32).to_le_bytes());
        for (name, value) in params {
            put_name(&mut out, name);
            match value {
                Computed::One(v) => {
                    out.push(tag(&v));
                    put_val(&mut out, &v);
                }
                Computed::Each(column) => {
                    out.push(match &column {
                        Col::I(_) => 3,
                        Col::F(_) => 4,
                        Col::B(_) => 5,
                    });
                    out.extend_from_slice(&(column.len() as u64).to_le_bytes());
                    put_column(&mut out, &column);
                }
            }
        }

        let values = self.persistent();
        out.extend_from_slice(&(values.len() as u32).to_le_bytes());
        for (name, value) in values {
            put_name(&mut out, name);
            match value {
                Computed::One(v) => {
                    out.extend_from_slice(&[tag(&v), 0]);
                    out.extend_from_slice(&1u64.to_le_bytes());
                    put_val(&mut out, &v);
                }
                Computed::Each(column) => {
                    let kind = match &column {
                        Col::I(_) => 0,
                        Col::F(_) => 1,
                        Col::B(_) => 2,
                    };
                    out.extend_from_slice(&[kind, 1]);
                    out.extend_from_slice(&(column.len() as u64).to_le_bytes());
                    put_column(&mut out, &column);
                }
            }
        }

        // Format 1: what each value is.
        let model = self.model();
        out.extend_from_slice(&(model.dims.len() as u32).to_le_bytes());
        for dim in &model.dims {
            put_name(&mut out, &dim.name);
            out.extend_from_slice(&(dim.members.len() as u32).to_le_bytes());
            for member in &dim.members {
                put_name(&mut out, member);
            }
        }
        out.extend_from_slice(&(model.entities.len() as u32).to_le_bytes());
        for entity in &model.entities {
            put_name(&mut out, &entity.name);
            out.extend_from_slice(&ids_hash(&entity.ids));
        }
        for &id in self.hashed_ids() {
            let d = &model.symbols[id];
            out.push(family(d.kind));
            out.extend_from_slice(&d.entity.map_or(u32::MAX, |e| e as u32).to_le_bytes());
            out.push(d.dims.len() as u8);
            for &dim in &d.dims {
                out.extend_from_slice(&(dim as u32).to_le_bytes());
            }
        }
        out
    }

    /// Rebuilds a run from [`Simulation::save`]. The model must be the one the save was
    /// made with. Commands still to come are supplied with [`Simulation::set_commands`].
    pub fn resume(model: Arc<Model>, bytes: &[u8]) -> Result<Simulation> {
        let snapshot = read(bytes)?;
        if snapshot.model_hash != model.model_hash {
            return Err(Error::Model("the save file was made with a different model".to_string()));
        }
        let mut simulation =
            Simulation::build(model, snapshot.seed, Params::Resolved(snapshot.params), Vec::new(), Vec::new())?;
        simulation.restore(snapshot.steps_done, snapshot.values)?;
        if simulation.state_hash() != snapshot.state_hash {
            return Err(corrupt());
        }
        Ok(simulation)
    }

    /// Stage S7.0: loads a save into the model it was made with, exactly, or into a changed
    /// model, carrying every value that still fits (see the save format, section
    /// "Loading into a changed model"). Parameters then come from the model, at `preset`
    /// with `overrides`, as for a new run. Returns the run and, when the model had changed,
    /// what the migration did.
    pub fn migrate(
        model: Arc<Model>,
        bytes: &[u8],
        preset: &str,
        overrides: Vec<(String, Value)>,
    ) -> Result<(Simulation, Option<Migration>)> {
        let snapshot = read(bytes)?;
        if snapshot.model_hash == model.model_hash {
            return Ok((Simulation::resume(model, bytes)?, None));
        }
        if snapshot.format == 0 {
            return Err(Error::Model(
                "the model files have changed since this game was saved, and saves this old cannot follow them"
                    .to_string(),
            ));
        }
        let source = Params::Scenario { preset: preset.to_string(), overrides };
        let mut simulation = Simulation::build(Arc::clone(&model), snapshot.seed, source, Vec::new(), Vec::new())?;

        // The saved value each name of the model takes: its own name first, then a rename.
        let renames: HashMap<&str, &str> = model.renamed.iter().map(|(a, b)| (a.as_str(), b.as_str())).collect();
        let mut target: HashMap<String, usize> = HashMap::new();
        let mut migration = Migration::default();
        for (i, (name, _)) in snapshot.values.iter().enumerate() {
            if model.sym_index.contains_key(name) {
                target.insert(name.clone(), i);
            }
        }
        for (i, (name, _)) in snapshot.values.iter().enumerate() {
            if model.sym_index.contains_key(name) {
                continue;
            }
            match renames.get(name.as_str()) {
                Some(&now) if !target.contains_key(now) => {
                    target.insert(now.to_string(), i);
                    migration.renamed.push((name.clone(), now.to_string()));
                }
                _ => migration.dropped.push(name.clone()),
            }
        }
        let carry = simulation.carry(snapshot.steps_done, |name| {
            let &i = target.get(name)?;
            let shape = &snapshot.shapes[i];
            Some(Before {
                family: shape.family,
                entity: shape.entity.clone(),
                dims: shape.dims.clone(),
                value: snapshot.values[i].1.clone(),
            })
        })?;
        migration.carried = simulation.hashed_ids().len() - carry.reset.len();
        migration.reset = carry.reset;
        migration.clamped = carry.clamped;
        // A renamed value that did not fit is not carried.
        migration.renamed.retain(|(_, now)| !migration.reset.contains(now));
        Ok((simulation, Some(migration)))
    }
}

/// Reads a save file of format 0 or 1.
fn read(bytes: &[u8]) -> Result<Snapshot> {
    let mut r = Reader { bytes, pos: 0 };
    if r.take(8)? != MAGIC {
        return Err(Error::Model("this is not a PoliSim save file".to_string()));
    }
    let format = r.u32()?;
    if format > FORMAT {
        return Err(Error::Model(format!("save format {format} is not supported by this engine")));
    }
    let _engine = r.name()?;
    let model_hash = r.hash()?;
    let seed = r.u64()?;
    let steps_done = r.u64()?;
    let state_hash = r.hash()?;

    let mut params = Vec::new();
    for _ in 0..r.u32()? {
        let name = r.name()?;
        let tag = r.u8()?;
        let value = match tag {
            0..=2 => Computed::One(r.val(tag)?),
            3..=5 => {
                let count = usize::try_from(r.u64()?).map_err(|_| corrupt())?;
                if count > bytes.len() {
                    return Err(corrupt());
                }
                Computed::Each(r.column(tag - 3, count)?)
            }
            _ => return Err(corrupt()),
        };
        params.push((name, value));
    }
    let mut values = Vec::new();
    for _ in 0..r.u32()? {
        let name = r.name()?;
        let (tag, shape) = (r.u8()?, r.u8()?);
        let count = usize::try_from(r.u64()?).map_err(|_| corrupt())?;
        // Each value takes at least one byte, so a count beyond the file is damage.
        if count > bytes.len() {
            return Err(corrupt());
        }
        let value = match (shape, tag) {
            (0, _) if count == 1 => Computed::One(r.val(tag)?),
            (1, 0..=2) => Computed::Each(r.column(tag, count)?),
            _ => return Err(corrupt()),
        };
        values.push((name, value));
    }
    let mut shapes = Vec::new();
    if format >= 1 {
        let mut dims = Vec::new();
        for _ in 0..r.u32()? {
            let name = r.name()?;
            let count = r.u32()? as usize;
            if count > bytes.len() {
                return Err(corrupt());
            }
            let members = (0..count).map(|_| r.name()).collect::<Result<Vec<_>>>()?;
            dims.push((name, members));
        }
        let mut entities = Vec::new();
        for _ in 0..r.u32()? {
            let name = r.name()?;
            entities.push((name, r.hash()?));
        }
        for _ in 0..values.len() {
            let family = r.u8()?;
            let entity = match r.u32()? {
                u32::MAX => None,
                e => Some(entities.get(e as usize).cloned().ok_or_else(corrupt)?),
            };
            let count = r.u8()?;
            let dims = (0..count)
                .map(|_| r.u32().and_then(|d| dims.get(d as usize).cloned().ok_or_else(corrupt)))
                .collect::<Result<Vec<_>>>()?;
            shapes.push(Shape { family, entity, dims });
        }
    }
    if r.pos != bytes.len() {
        return Err(corrupt());
    }
    Ok(Snapshot { format, model_hash, seed, steps_done, state_hash, params, values, shapes })
}
