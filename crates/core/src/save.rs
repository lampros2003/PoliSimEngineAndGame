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
//! format                          u32, currently 0
//! engine version                  u16 length + UTF-8
//! model hash                      32 bytes
//! seed                            u64
//! steps completed                 u64
//! state hash at the time of save  32 bytes
//! parameter count                 u32
//!   name                          u16 length + UTF-8
//!   type                          u8: 0 whole number, 1 real, 2 true/false
//!   value                         8 bytes (1 byte for true/false)
//! value count                     u32, the hashed symbols in hash order
//!   name                          u16 length + UTF-8
//!   type                          u8, as above
//!   shape                         u8: 0 one value, 1 one value per record
//!   count                         u64
//!   values                        count * 8 bytes (count bytes for true/false)
//! ```

use std::sync::Arc;

use crate::error::{Error, Result};
use crate::model::Model;
use crate::program::{Col, Val};
use crate::sim::{Computed, Params, Simulation};

const MAGIC: &[u8; 8] = b"PSIMSAVE";
const FORMAT: u32 = 0;

fn put_name(out: &mut Vec<u8>, name: &str) {
    out.extend_from_slice(&(name.len() as u16).to_le_bytes());
    out.extend_from_slice(name.as_bytes());
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
            out.push(tag(&value));
            put_val(&mut out, &value);
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
                    match &column {
                        Col::I(c) => c.iter().for_each(|v| out.extend_from_slice(&v.to_le_bytes())),
                        Col::F(c) => c.iter().for_each(|v| out.extend_from_slice(&v.to_bits().to_le_bytes())),
                        Col::B(c) => out.extend(c.iter().map(|v| *v as u8)),
                    }
                }
            }
        }
        out
    }

    /// Rebuilds a run from [`Simulation::save`]. The model must be the one the save was
    /// made with. Commands still to come are supplied with [`Simulation::set_commands`].
    pub fn resume(model: Arc<Model>, bytes: &[u8]) -> Result<Simulation> {
        let mut r = Reader { bytes, pos: 0 };
        if r.take(8)? != MAGIC {
            return Err(Error::Model("this is not a PoliSim save file".to_string()));
        }
        let format = r.u32()?;
        if format != FORMAT {
            return Err(Error::Model(format!("save format {format} is not supported by this engine")));
        }
        let _engine = r.name()?;
        if r.hash()? != model.model_hash {
            return Err(Error::Model("the save file was made with a different model".to_string()));
        }
        let seed = r.u64()?;
        let steps_done = r.u64()?;
        let state_hash = r.hash()?;

        let mut params = Vec::new();
        for _ in 0..r.u32()? {
            let name = r.name()?;
            let tag = r.u8()?;
            params.push((name, r.val(tag)?));
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
                (1, 0) => {
                    let mut column = Vec::with_capacity(count);
                    for _ in 0..count {
                        column.push(r.u64()? as i64);
                    }
                    Computed::Each(Col::I(column))
                }
                (1, 1) => {
                    let mut column = Vec::with_capacity(count);
                    for _ in 0..count {
                        column.push(f64::from_bits(r.u64()?));
                    }
                    Computed::Each(Col::F(column))
                }
                (1, 2) => Computed::Each(Col::B(r.take(count)?.iter().map(|b| *b != 0).collect())),
                _ => return Err(corrupt()),
            };
            values.push((name, value));
        }
        if r.pos != bytes.len() {
            return Err(corrupt());
        }

        let mut simulation = Simulation::build(model, seed, Params::Resolved(params), Vec::new(), Vec::new())?;
        simulation.restore(steps_done, values)?;
        if simulation.state_hash() != state_hash {
            return Err(corrupt());
        }
        Ok(simulation)
    }
}
