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
    /// S10.6: `ln`, `sqrt` and `pow`, by the fixed algorithms of docs/spec/02
    /// ([`ln_fixed`], [`sqrt_fixed`], [`pow_fixed`]).
    Ln(R, R),
    Sqrt(R, R),
    Pow(R, R, R),
    ToInt(Rounding, R, R),
    /// destination, condition, value if true, value if false
    SelI(R, R, R, R),
    SelF(R, R, R, R),
    SelB(R, R, R, R),
    /// destination, numerator, denominator, fallback
    SafeDiv(R, R, R, R),
    /// destination, a, b, c: floor(a * b / c)
    MulDiv(R, R, R, R),
    /// Stage S10.3: destination, a, b: floor(a / b), b positive
    DivI(R, R, R),
    /// Stage S10.3: destination, a, b: a - b * floor(a / b), b positive
    ModI(R, R, R),
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
    Sum {
        group: usize,
    },
    /// `cohort_shift`: cells move one member up along a dimension with this stride and size.
    Shift {
        stride: usize,
        size: usize,
    },
    /// Stage S10.3: `largest` and `smallest`: each run of `group` consecutive cells becomes its
    /// largest (or smallest) cell, folding from the first as `max` (`min`) does.
    Largest {
        group: usize,
    },
    Smallest {
        group: usize,
    },
    /// Stage S10.3: `sum_by`: the cells come in runs of `group` (one run for each cell of the
    /// result with its target dimension left out); each is added to the result's cell that
    /// its key names (see [`SumBy`]).
    SumBy {
        group: usize,
    },
}

/// Format 1: a program evaluated over `cells` cells before the program that uses it.
#[derive(Clone, Debug)]
pub struct Sub {
    pub kind: SubKind,
    pub cells: usize,
    pub prog: Program,
    /// Stage S10.3: for `sum_by`, the key and where each run goes.
    pub by: Option<Box<SumBy>>,
}

/// Stage S10.3: `sum_by(x, d, key, t)`. The sub-program and the key are evaluated over the
/// result's dimensions without `t`, then `d`; run `r` (all of `d` for one cell) goes to the
/// result's cells `bases[r] + stride * position`, the position being the key less `first`.
#[derive(Clone, Debug)]
pub struct SumBy {
    pub key: Program,
    pub bases: Vec<u32>,
    pub stride: usize,
    /// Members of `t`, its first member (0 for a list), and its name for errors.
    pub size: usize,
    pub first: i64,
    pub dim: String,
    /// Cells of the result.
    pub cells: usize,
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
            + self.subs.iter().map(|s| s.prog.op_count() + s.by.as_ref().map_or(0, |b| b.key.op_count())).sum::<usize>()
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
    // LOG2_E is the double the specification writes as 1.4426950408889634.
    let k = (x * std::f64::consts::LOG2_E).round_ties_even();
    let r = (x - k * 0.6931471803691238) - k * 1.9082149292705877e-10;
    let mut p = 1.6059043836821613e-10;
    for c in C {
        p = p * r + c;
    }
    // 2^k for k in [-1022, 1023], built from its bits: exact.
    p * f64::from_bits(((k as i64 + 1023) as u64) << 52)
}

/// The natural logarithm by the fixed algorithm of docs/spec/02-formula-language-v0.md
/// (stage S10.6): only rounded `+`, `-`, `*`, `/` (no fused multiply-add) and an exact split
/// of `x` into a fraction and a power of two. A port of the oracle's `ln_fixed`.
pub fn ln_fixed(x: f64) -> f64 {
    const LG: [f64; 7] = [
        0.6666666666666735,
        0.3999999999940942,
        0.2857142874366239,
        0.22222198432149784,
        0.1818357216161805,
        0.15313837699209373,
        0.14798198605116586,
    ];
    if x.is_nan() || x < 0.0 {
        return f64::NAN;
    }
    if x == 0.0 {
        return f64::NEG_INFINITY;
    }
    if x == f64::INFINITY {
        return x;
    }
    let (mut m, mut e) = frexp(x);
    // 1/sqrt(2), the double 0.7071067811865476 of the spec.
    if m < std::f64::consts::FRAC_1_SQRT_2 {
        m *= 2.0;
        e -= 1;
    }
    let f = m - 1.0;
    let s = f / (2.0 + f);
    let z = s * s;
    let w = z * z;
    let r = z * (LG[0] + w * (LG[2] + w * (LG[4] + w * LG[6]))) + w * (LG[1] + w * (LG[3] + w * LG[5]));
    let half_square = 0.5 * f * f;
    let k = e as f64;
    k * 0.6931471803691238 - ((half_square - (s * (half_square + r) + k * 1.9082149292705877e-10)) - f)
}

/// `x = m * 2^e` with `m` in [0.5, 1), for a finite positive `x`: exact, as Python's
/// `math.frexp`. A subnormal `x` is first scaled by 2^54, which is exact.
fn frexp(x: f64) -> (f64, i32) {
    let (x, shift) = if x < f64::MIN_POSITIVE { (x * 18014398509481984.0, -54) } else { (x, 0) };
    let bits = x.to_bits();
    let e = ((bits >> 52) & 0x7ff) as i32 - 1022;
    (f64::from_bits((bits & !(0x7ff << 52)) | (1022 << 52)), e + shift)
}

/// The square root, correctly rounded as IEEE 754 requires; not-a-number below zero.
pub fn sqrt_fixed(x: f64) -> f64 {
    if x < 0.0 { f64::NAN } else { x.sqrt() }
}

/// `x` to the power `y` (stage S10.6), by docs/spec/02: for a whole `y` of at most 1,024 in
/// size, by repeated squaring (so `pow(5, 2)` is 25 and a negative `x` is allowed);
/// otherwise `exp(y * ln(x))` by the fixed algorithms, with cases for zero, infinity and
/// not-a-number. A port of the oracle's `pow_fixed`.
pub fn pow_fixed(x: f64, y: f64) -> f64 {
    if y.is_nan() {
        return f64::NAN;
    }
    if y == y.floor() && y.abs() <= 1024.0 {
        let (mut n, mut r, mut b) = (y.abs() as u32, 1.0, x);
        while n > 0 {
            if n % 2 == 1 {
                r *= b;
            }
            n /= 2;
            b *= b;
        }
        return if y < 0.0 { 1.0 / r } else { r };
    }
    if x.is_nan() {
        return f64::NAN;
    }
    if x < 0.0 {
        return f64::NAN;
    }
    if x == 0.0 {
        return if y > 0.0 { 0.0 } else { f64::INFINITY };
    }
    if x == f64::INFINITY {
        return if y > 0.0 { f64::INFINITY } else { 0.0 };
    }
    exp_fixed(y * ln_fixed(x))
}

#[cfg(test)]
mod tests {
    use super::{exp_fixed, ln_fixed, pow_fixed, sqrt_fixed};

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
        assert_eq!(std::f64::consts::LOG2_E.to_bits(), 0x3FF7_1547_652B_82FE);
    }

    #[test]
    fn ln_is_within_two_units_in_the_last_place() {
        // Fixed sweeps against the platform's library: near 1, over [0.5, 2], and over the
        // whole range by powers.
        let mut x = 0.999;
        while x < 1.001 {
            assert!(ulps(ln_fixed(x), x.ln()) <= 2, "{x}");
            x += 1.3e-7;
        }
        let mut x = 0.5;
        while x < 2.0 {
            assert!(ulps(ln_fixed(x), x.ln()) <= 2, "{x}");
            x += 1.7e-5;
        }
        let mut p: f64 = -744.0;
        while p < 709.0 {
            let x = p.exp();
            assert!(ulps(ln_fixed(x), x.ln()) <= 2, "{x}");
            p += 0.0071;
        }
        assert_eq!(std::f64::consts::FRAC_1_SQRT_2.to_bits(), 0x3FE6_A09E_667F_3BCD);
        assert_eq!(ln_fixed(1.0).to_bits(), 0.0f64.to_bits());
        assert_eq!(ln_fixed(2.0), std::f64::consts::LN_2);
        assert_eq!(ln_fixed(5e-324), -744.4400719213812);
        assert_eq!(ln_fixed(0.0), f64::NEG_INFINITY);
        assert_eq!(ln_fixed(f64::INFINITY), f64::INFINITY);
        assert!(ln_fixed(-1.0).is_nan() && ln_fixed(f64::NAN).is_nan());
    }

    #[test]
    fn sqrt_and_pow_at_their_edges() {
        assert_eq!(sqrt_fixed(2.0), std::f64::consts::SQRT_2);
        assert!(sqrt_fixed(-1.0).is_nan());
        assert_eq!(sqrt_fixed(-0.0).to_bits(), (-0.0f64).to_bits());
        assert_eq!(pow_fixed(2.0, 10.0), 1024.0);
        assert_eq!((pow_fixed(5.0, 2.0), pow_fixed(-2.0, 3.0), pow_fixed(-2.0, -2.0)), (25.0, -8.0, 0.25));
        assert_eq!((pow_fixed(-2.0, 0.0), pow_fixed(f64::NAN, 0.0)), (1.0, 1.0));
        assert!(pow_fixed(-2.0, 2.5).is_nan());
        assert_eq!(
            (pow_fixed(0.0, 2.0), pow_fixed(0.0, -1.0), pow_fixed(-0.0, -1.0)),
            (0.0, f64::INFINITY, f64::NEG_INFINITY)
        );
        assert_eq!((pow_fixed(0.0, 0.5), pow_fixed(0.0, -0.5)), (0.0, f64::INFINITY));
        assert_eq!((pow_fixed(f64::INFINITY, 0.5), pow_fixed(f64::INFINITY, -0.5)), (f64::INFINITY, 0.0));
        assert!(pow_fixed(f64::NAN, 0.5).is_nan() && pow_fixed(1.0, f64::NAN).is_nan());
        assert_eq!(pow_fixed(2.0, 1025.0), exp_fixed(1025.0 * ln_fixed(2.0)));
        assert_eq!(pow_fixed(1.05, 0.5), exp_fixed(0.5 * ln_fixed(1.05)));
    }
}
