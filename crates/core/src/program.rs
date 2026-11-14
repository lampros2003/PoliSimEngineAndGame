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
    /// S5.1: `exp`, by the fixed algorithm of docs/spec/02 ([`exp_fixed`]).
    Exp(R, R),
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
    /// Format 1. destination, source, gather: the value of a dimensioned element at
    /// `gathers[g][cell]` for each cell of the program's domain.
    LoadGI(R, Src, u16),
    LoadGF(R, Src, u16),
    LoadGB(R, Src, u16),
    /// destination, coordinate table: `coords[c][cell]`.
    Coord(R, u16),
    /// destination, index use: `x[d: e, ...]`.
    IndexI(R, u16),
    IndexF(R, u16),
    IndexB(R, u16),
    /// destination, sub-program: its result at each cell of this program's domain.
    LoadSubI(R, u16),
    LoadSubF(R, u16),
    /// destination, grouped aggregate, gather: `wsum_by` / `wcount_by`, read at each cell's
    /// position along the grouping dimension.
    LoadAggByI(R, u16, u16),
    LoadAggByF(R, u16, u16),
}

/// Format 1 (S4.0): `wsum_by` or `wcount_by`: a per-record value and key, summed by key.
#[derive(Clone, Debug)]
pub struct AggBy {
    pub name: &'static str,
    pub kind: AggKind,
    pub entity: usize,
    pub value: Program,
    pub key: Program,
    pub dim: String,
    /// Subtracted from a key to give the position: a range's first member, else 0.
    pub first: i64,
    pub size: usize,
}

/// Format 1: one fixed dimension of an index, `d: e`.
#[derive(Clone, Debug)]
pub struct Fixed {
    pub dim: String,
    /// Register holding the coordinate: a member of a range, or a position in a list.
    pub reg: R,
    /// Subtracted from the coordinate to give the position: a range's first member, else 0.
    pub first: i64,
    pub size: u32,
    pub stride: u32,
}

/// Format 1: `x[d: e, ...]` in a program.
#[derive(Clone, Debug)]
pub struct IndexUse {
    pub name: String,
    pub src: Src,
    /// Flat offset contributed by the dimensions in scope, per cell of the domain; empty
    /// when every dimension is fixed.
    pub base: Vec<u32>,
    /// The fixed dimensions, in the order written.
    pub fixed: Vec<Fixed>,
}

/// Format 1: what happens to a sub-program's column.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SubKind {
    /// `sum`: each run of `group` consecutive cells becomes one cell.
    Sum { group: usize },
    /// `cohort_shift`: cells move one member up along a dimension with this stride and size.
    Shift { stride: usize, size: usize },
}

/// Format 1: a program evaluated over `cells` cells before the program that uses it.
#[derive(Clone, Debug)]
pub struct Sub {
    pub kind: SubKind,
    pub cells: usize,
    pub prog: Program,
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
    /// Format 1: maps from this program's cells to cells of dimensioned elements.
    pub gathers: Vec<Vec<u32>>,
    pub coords: Vec<Vec<i64>>,
    pub indexes: Vec<IndexUse>,
    pub subs: Vec<Sub>,
    pub aggs_by: Vec<AggBy>,
}

impl Program {
    /// Instructions in this program and everything it evaluates on the way.
    pub fn op_count(&self) -> usize {
        self.ops.len()
            + self.aggs.iter().map(|a| a.prog.op_count()).sum::<usize>()
            + self.tables.iter().flat_map(|t| t.lows.iter().chain(&t.rates)).map(Program::op_count).sum::<usize>()
            + self.subs.iter().map(|s| s.prog.op_count()).sum::<usize>()
            + self.aggs_by.iter().map(|a| a.value.op_count() + a.key.op_count()).sum::<usize>()
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

/// `exp(x)` by the fixed algorithm of docs/spec/02-formula-language-v0.md, so that every
/// machine gives the same bits: only rounded `+`, `-`, `*` (no fused multiply-add) and an
/// exact scaling by a power of two. A port of the oracle's `exp_fixed`.
pub fn exp_fixed(x: f64) -> f64 {
    const C: [f64; 13] = [
        2.08767569878681e-09,
        2.505210838544172e-08,
        2.755731922398589e-07,
        2.7557319223985893e-06,
        2.48015873015873e-05,
        0.0001984126984126984,
        0.001388888888888889,
        0.008333333333333333,
        0.041666666666666664,
        0.16666666666666666,
        0.5,
        1.0,
        1.0,
    ];
    if x.is_nan() {
        return x;
    }
    if x > 709.0 {
        return f64::INFINITY;
    }
    if x < -708.0 {
        return 0.0;
    }
    let k = (x * 1.4426950408889634).round_ties_even();
    let r = (x - k * 0.6931471803691238) - k * 1.9082149292705877e-10;
    let mut p = 1.6059043836821613e-10;
    for c in C {
        p = p * r + c;
    }
    // 2^k for k in [-1022, 1023], built from its bits: exact.
    p * f64::from_bits(((k as i64 + 1023) as u64) << 52)
}

#[cfg(test)]
mod tests {
    use super::exp_fixed;

    fn ulps(a: f64, b: f64) -> u64 {
        (a.to_bits() as i64 - b.to_bits() as i64).unsigned_abs()
    }

    #[test]
    fn exp_is_within_two_units_in_the_last_place() {
        // A fixed sweep over the range against the platform's library.
        let mut x = -708.0;
        while x < 709.0 {
            assert!(ulps(exp_fixed(x), x.exp()) <= 2, "{x}");
            x += 0.0137;
        }
        assert_eq!(exp_fixed(0.0), 1.0);
        assert_eq!(exp_fixed(709.5), f64::INFINITY);
        assert_eq!(exp_fixed(-708.5), 0.0);
        assert!(exp_fixed(f64::NAN).is_nan());
    }
}
