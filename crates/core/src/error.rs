//! The three ways the engine can refuse to continue.

use std::fmt;

/// An engine error. The split mirrors the oracle's three exception types.
#[derive(Debug, Clone, PartialEq)]
pub enum Error {
    /// The model files are inconsistent. Raised while loading.
    Model(String),
    /// A formula is malformed: syntax, type or unit error. Raised while loading.
    Formula(String),
    /// A formula or posting produced an illegal value while running.
    Sim(String),
}

impl Error {
    pub fn message(&self) -> &str {
        match self {
            Error::Model(m) | Error::Formula(m) | Error::Sim(m) => m,
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.message())
    }
}

impl std::error::Error for Error {}

pub type Result<T> = std::result::Result<T, Error>;

pub(crate) fn model_err<T>(message: impl Into<String>) -> Result<T> {
    Err(Error::Model(message.into()))
}

pub(crate) fn sim_err<T>(message: impl Into<String>) -> Result<T> {
    Err(Error::Sim(message.into()))
}
