//! PoliSim simulation engine.
//!
//! Loads a model written in model-file format 0, compiles its formulas to bytecode and
//! steps it. The behaviour is defined by docs/spec/ and by the Python oracle in
//! `oracle/`; this crate is correct when its state hash equals the oracle's on every step.
//!
//! ```no_run
//! use std::sync::Arc;
//! use polisim_core::{RunConfig, Simulation, load_model};
//!
//! let model = Arc::new(load_model("models/toy".as_ref())?);
//! let mut sim = Simulation::new(model, RunConfig { seed: 1, preset: "central".into(), ..Default::default() })?;
//! let row = sim.step()?;
//! println!("step {} hash {:02x?}", row.step, &row.hash[..4]);
//! # Ok::<(), polisim_core::Error>(())
//! ```

pub mod compile;
pub mod error;
pub mod model;
pub mod program;
pub mod pyfmt;
pub mod rng;
pub mod sim;
pub mod syntax;
pub mod units;
pub mod vm;

pub use error::{Error, Result};
pub use model::{Model, Scenario, load_model, load_scenario};
pub use program::{Col, Ty, Val};
pub use sim::{Computed, Row, RunConfig, Simulation};

/// Engine version, recorded in save files.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
