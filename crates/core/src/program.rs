//! Values and the bytecode a formula compiles to.

use crate::units::Unit;

/// The three kinds of value (engine contract, section 1).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Ty {
    Int,
    Real,
    Bool,
}

impl Ty {
    pub fn name(self) -> &'static str {
        match self {
            Ty::Int => "int",
            Ty::Real => "real",
            Ty::Bool => "bool",
        }
    }
}

/// One value.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Val {
    I(i64),
    F(f64),
    B(bool),
}

/// One value per record of an entity.
#[derive(Clone, Debug, PartialEq)]
pub enum Col {
    I(Vec<i64>),
    F(Vec<f64>),
    B(Vec<bool>),
}

impl Col {
    pub fn len(&self) -> usize {
        match self {
            Col::I(v) => v.len(),
            Col::F(v) => v.len(),
            Col::B(v) => v.len(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn filled(value: Val, count: usize) -> Col {
        match value {
            Val::I(v) => Col::I(vec![v; count]),
            Val::F(v) => Col::F(vec![v; count]),
            Val::B(v) => Col::B(vec![v; count]),
        }
    }
}

/// A register index. Whole numbers, reals and booleans live in three separate files.
pub type R = u16;

/// Where a load reads from: a symbol's current value, or its value at the end of the
/// previous step.
#[derive(Clone, Copy, Debug)]
pub struct Src {
    pub sym: u32,
    pub lagged: bool,
}

#[derive(Clone, Copy, Debug)]
pub enum Cmp {
    Lt,
    Le,
    Gt,
    Ge,
    Eq,
    Ne,
}

#[derive(Clone, Copy, Debug)]
pub enum Rounding {
    Round,
    Floor,
    Ceil,
}

/// Three-address register code. The first register is always the destination, and the
/// compiler gives every instruction a fresh destination, so a destination never aliases
/// an operand. Each instruction is applied to a whole block of records.
#[derive(Clone, Copy, Debug)]
pub enum Op {
    ConstI(R, i64),
    ConstF(R, f64),
    ConstB(R, bool),
    /// National value, repeated for every record of the block.
    LoadSI(R, Src),
    LoadSF(R, Src),
    LoadSB(R, Src),
    /// Per-record column.
    LoadCI(R, Src),
    LoadCF(R, Src),
    LoadCB(R, Src),
    /// Result of the program's k-th aggregate.
    LoadAggI(R, u16),
    LoadAggF(R, u16),
    NegI(R, R),
    NegF(R, R),
    NotB(R, R),
    AddI(R, R, R),
    SubI(R, R, R),
    MulI(R, R, R),
    AddF(R, R, R),
    SubF(R, R, R),
    MulF(R, R, R),
    DivF(R, R, R),
    IToF(R, R),
    CmpI(Cmp, R, R, R),
    CmpF(Cmp, R, R, R),
    /// Equality (`true`) or inequality (`false`) of two booleans.
    CmpB(bool, R, R, R),
    AndB(R, R, R),
    OrB(R, R, R),
    MinI(R, R, R),
    MaxI(R, R, R),
    MinF(R, R, R),
    MaxF(R, R, R),
    ClampI(R, R, R, R),
    ClampF(R, R, R, R),
    AbsI(R, R),
    AbsF(R, R),
    ToInt(Rounding, R, R),
    /// destination, condition, value if true, value if false
    SelI(R, R, R, R),
    SelF(R, R, R, R),
    SelB(R, R, R, R),
    /// destination, numerator, denominator, fallback
    SafeDiv(R, R, R, R),
    /// destination, a, b, c: floor(a * b / c)
    MulDiv(R, R, R, R),
    /// destination, amount, index into the program's table uses
    Marginal(R, R, u16),
    /// destination, stream id, one draw per record (`true`) or the national draw
    Rand(R, u32, bool),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AggKind {
    SumInt,
    SumReal,
    Count,
}

/// `wsum` or `wcount` inside a national formula: a per-record program and a reduction.
#[derive(Clone, Debug)]
pub struct Agg {
    pub kind: AggKind,
    pub entity: usize,
    pub prog: Program,
}

/// One use of a marginal-rate table: a national program per threshold and per rate.
#[derive(Clone, Debug)]
pub struct TableUse {
    pub table: usize,
    pub lows: Vec<Program>,
    pub rates: Vec<Program>,
}

/// A compiled formula.
#[derive(Clone, Debug)]
pub struct Program {
    pub ops: Vec<Op>,
    pub n_i: u16,
    pub n_f: u16,
    pub n_b: u16,
    /// Register holding the result, in the file for `ty`.
    pub result: R,
    pub ty: Ty,
    pub aggs: Vec<Agg>,
    pub tables: Vec<TableUse>,
}

impl Program {
    /// Instructions in this program and everything it evaluates on the way.
    pub fn op_count(&self) -> usize {
        self.ops.len()
            + self.aggs.iter().map(|a| a.prog.op_count()).sum::<usize>()
            + self.tables.iter().flat_map(|t| t.lows.iter().chain(&t.rates)).map(Program::op_count).sum::<usize>()
    }
}

/// A compiled formula plus what it reads, by symbol index.
#[derive(Clone, Debug)]
pub struct Compiled {
    pub prog: Program,
    /// Symbols read at their current-step value.
    pub deps: Vec<usize>,
    /// Symbols read through `prev()`.
    pub lagged: Vec<usize>,
    /// Unit of the result; `None` only for a bare literal zero.
    pub unit: Option<Unit>,
}
