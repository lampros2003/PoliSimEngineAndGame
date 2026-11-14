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
pub mod describe;
pub mod error;
pub mod explain;
pub mod model;
pub mod program;
pub mod pyfmt;
pub mod rng;
pub mod save;
pub mod session;
pub mod sim;
pub mod syntax;
pub mod text;
pub mod units;
pub mod vm;

pub use describe::Catalogue;
pub use error::{Error, Result};
pub use explain::{Explanation, Num, Part};
pub use model::{
    DilemmaInfo, DilemmaOption, ModInfo, Model, Scenario, load_model, load_model_with_mods, load_scenario,
    load_scenario_with_mods, read_mod,
};
pub use program::{Col, Ty, Val};
pub use save::Migration;
pub use session::Session;
pub use sim::{Computed, Row, RunConfig, Simulation, Vote, bill_cost, check_lever};
pub use text::{Text, languages, load_text};
/// A parsed TOML document, for clients that read scenario files themselves.
pub use toml::Table as RawTable;
/// A raw value as written in a model or scenario file, before it is given a type.
pub use toml::Value as RawValue;

/// Engine version, recorded in save files.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
