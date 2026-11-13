//! The block-wise interpreter.
//!
//! Each instruction is applied to a block of records before the next instruction runs.
//! A national formula is the same thing with a block of one. Evaluation is strict (engine
//! contract, section 7): every instruction runs for every record, and an illegal result
//! anywhere fails the whole formula.

use crate::model::Entity;
use crate::program::{Agg, AggKind, Cmp, Col, Op, Program, Rounding, Src, Ty, Val};
use crate::rng::uniform;

/// Records per block. Stage S0 measured 64 to 1,024 as equally good.
pub const BLOCK: usize = 256;

const TWO_POW_63: f64 = 9_223_372_036_854_775_808.0;

type Check<T> = Result<T, String>;

/// Everything a formula can read.
pub struct EvalCtx<'a> {
    pub scal: &'a [Val],
    pub cols: &'a [Col],
    pub prev_scal: &'a [Val],
    pub prev_cols: &'a [Col],
    pub entities: &'a [Entity],
    pub seed: u64,
    /// Index of the step being computed.
    pub step: u32,
}

struct Regs {
    i: Vec<Vec<i64>>,
    f: Vec<Vec<f64>>,
    b: Vec<Vec<bool>>,
}

impl Regs {
    fn new(prog: &Program, len: usize) -> Regs {
        Regs {
            i: vec![vec![0; len]; prog.n_i as usize],
            f: vec![vec![0.0; len]; prog.n_f as usize],
            b: vec![vec![false; len]; prog.n_b as usize],
        }
    }
}

/// Values a program needs before its instructions run: aggregates and table bands.
struct Prepared {
    aggs: Vec<Val>,
    tables: Vec<(Vec<i64>, Vec<f64>)>,
}

fn overflow<T>() -> Check<T> {
    Err("integer overflow (result does not fit in 64 bits)".to_string())
}

fn internal<T>(what: &str) -> Check<T> {
    Err(format!("internal error: {what}"))
}

fn prepare(prog: &Program, cx: &EvalCtx) -> Check<Prepared> {
    let mut tables = Vec::with_capacity(prog.tables.len());
    for table in &prog.tables {
        let mut lows = Vec::with_capacity(table.lows.len());
        let mut rates = Vec::with_capacity(table.rates.len());
        for low in &table.lows {
            match eval_scalar(low, cx)? {
                Val::I(v) => lows.push(v),
                _ => return internal("table threshold is not a whole number"),
            }
        }
        for rate in &table.rates {
            match eval_scalar(rate, cx)? {
                Val::F(v) => rates.push(v),
                _ => return internal("table rate is not a real"),
            }
        }
        tables.push((lows, rates));
    }
    let mut aggs = Vec::with_capacity(prog.aggs.len());
    for agg in &prog.aggs {
        aggs.push(eval_agg(agg, cx)?);
    }
    Ok(Prepared { aggs, tables })
}

/// Evaluates a national formula.
pub fn eval_scalar(prog: &Program, cx: &EvalCtx) -> Check<Val> {
    let prepared = prepare(prog, cx)?;
    let mut regs = Regs::new(prog, 1);
    run_block(prog, cx, None, 0, 1, &mut regs, &prepared)?;
    let r = prog.result as usize;
    Ok(match prog.ty {
        Ty::Int => Val::I(regs.i[r][0]),
        Ty::Real => Val::F(regs.f[r][0]),
        Ty::Bool => Val::B(regs.b[r][0]),
    })
}

/// Evaluates a per-record formula for every record of `entity`.
pub fn eval_column(prog: &Program, entity: usize, cx: &EvalCtx) -> Check<Col> {
    let prepared = prepare(prog, cx)?;
    let count = cx.entities[entity].ids.len();
    let mut regs = Regs::new(prog, BLOCK.min(count.max(1)));
    let r = prog.result as usize;
    let mut out = match prog.ty {
        Ty::Int => Col::I(Vec::with_capacity(count)),
        Ty::Real => Col::F(Vec::with_capacity(count)),
        Ty::Bool => Col::B(Vec::with_capacity(count)),
    };
    let mut start = 0;
    while start < count {
        let len = BLOCK.min(count - start);
        run_block(prog, cx, Some(entity), start, len, &mut regs, &prepared)?;
        match &mut out {
            Col::I(v) => v.extend_from_slice(&regs.i[r][..len]),
            Col::F(v) => v.extend_from_slice(&regs.f[r][..len]),
            Col::B(v) => v.extend_from_slice(&regs.b[r][..len]),
        }
        start += len;
    }
    Ok(out)
}

/// `wsum` and `wcount`. Whole-number sums are exact; a real sum is accumulated in
/// ascending record order, each term being `real(weight) * value`.
fn eval_agg(agg: &Agg, cx: &EvalCtx) -> Check<Val> {
    let prog = &agg.prog;
    let prepared = prepare(prog, cx)?;
    let weights = &cx.entities[agg.entity].weights;
    let count = weights.len();
    let mut regs = Regs::new(prog, BLOCK.min(count.max(1)));
    let r = prog.result as usize;
    let mut whole: i128 = 0;
    let mut real: f64 = 0.0;
    let mut start = 0;
    while start < count {
        let len = BLOCK.min(count - start);
        run_block(prog, cx, Some(agg.entity), start, len, &mut regs, &prepared)?;
        let w = &weights[start..start + len];
        match agg.kind {
            AggKind::SumInt => {
                for (w, v) in w.iter().zip(&regs.i[r][..len]) {
                    whole = match whole.checked_add(*w as i128 * *v as i128) {
                        Some(total) => total,
                        None => return overflow(),
                    };
                }
            }
            AggKind::SumReal => {
                for (w, v) in w.iter().zip(&regs.f[r][..len]) {
                    real += *w as f64 * *v;
                }
            }
            AggKind::Count => {
                for (w, c) in w.iter().zip(&regs.b[r][..len]) {
                    if *c {
                        whole += *w as i128;
                    }
                }
            }
        }
        start += len;
    }
    match agg.kind {
        AggKind::SumReal => Ok(Val::F(real)),
        _ => match i64::try_from(whole) {
            Ok(total) => Ok(Val::I(total)),
            Err(_) => overflow(),
        },
    }
}

/// Marginal-rate schedule (formula language, `marginal`). Band k covers
/// `[lows[k], lows[k+1])` and the last band is open.
pub fn marginal_amount(x: i64, lows: &[i64], rates: &[f64]) -> Check<i64> {
    let mut acc = 0.0f64;
    let last = lows.len() - 1;
    for (k, low) in lows.iter().enumerate() {
        let mut part = x as i128 - *low as i128;
        if k < last {
            let width = lows[k + 1] as i128 - *low as i128;
            if width < 0 {
                return Err("band thresholds must not descend".to_string());
            }
            if part > width {
                part = width;
            }
        }
        if part < 0 {
            part = 0;
        }
        let Ok(part) = i64::try_from(part) else { return overflow() };
        acc += rates[k] * part as f64;
    }
    real_to_int(acc, Rounding::Round)
}

/// `round` is half to even, `floor` is toward minus infinity, `ceil` toward plus infinity.
#[inline]
pub fn real_to_int(x: f64, mode: Rounding) -> Check<i64> {
    let r = match mode {
        Rounding::Round => x.round_ties_even(),
        Rounding::Floor => x.floor(),
        Rounding::Ceil => x.ceil(),
    };
    // Also false for not-a-number.
    if (-TWO_POW_63..TWO_POW_63).contains(&r) {
        Ok(r as i64)
    } else {
        Err("conversion to a whole number of a value that is not finite or does not fit in 64 bits".to_string())
    }
}

fn scalar<'a>(cx: &'a EvalCtx, src: Src) -> &'a Val {
    if src.lagged { &cx.prev_scal[src.sym as usize] } else { &cx.scal[src.sym as usize] }
}

fn column<'a>(cx: &'a EvalCtx, src: Src) -> &'a Col {
    if src.lagged { &cx.prev_cols[src.sym as usize] } else { &cx.cols[src.sym as usize] }
}

macro_rules! pick {
    ($file:expr, $len:expr, $d:expr, $a:expr) => {{
        let Ok([d, a]) = $file.get_disjoint_mut([$d as usize, $a as usize]) else { return internal("register clash") };
        (&mut d[..$len], &a[..$len])
    }};
    ($file:expr, $len:expr, $d:expr, $a:expr, $b:expr) => {{
        let Ok([d, a, b]) = $file.get_disjoint_mut([$d as usize, $a as usize, $b as usize]) else {
            return internal("register clash");
        };
        (&mut d[..$len], &a[..$len], &b[..$len])
    }};
    ($file:expr, $len:expr, $d:expr, $a:expr, $b:expr, $c:expr) => {{
        let Ok([d, a, b, c]) = $file.get_disjoint_mut([$d as usize, $a as usize, $b as usize, $c as usize]) else {
            return internal("register clash");
        };
        (&mut d[..$len], &a[..$len], &b[..$len], &c[..$len])
    }};
}

#[inline]
fn compare<T: PartialOrd>(cmp: Cmp, x: T, y: T) -> bool {
    match cmp {
        Cmp::Lt => x < y,
        Cmp::Le => x <= y,
        Cmp::Gt => x > y,
        Cmp::Ge => x >= y,
        Cmp::Eq => x == y,
        Cmp::Ne => x != y,
    }
}

fn run_block(
    prog: &Program,
    cx: &EvalCtx,
    entity: Option<usize>,
    start: usize,
    len: usize,
    regs: &mut Regs,
    prepared: &Prepared,
) -> Check<()> {
    let end = start + len;
    for op in &prog.ops {
        match *op {
            Op::ConstI(d, v) => regs.i[d as usize][..len].fill(v),
            Op::ConstF(d, v) => regs.f[d as usize][..len].fill(v),
            Op::ConstB(d, v) => regs.b[d as usize][..len].fill(v),
            Op::LoadSI(d, src) => match scalar(cx, src) {
                Val::I(v) => regs.i[d as usize][..len].fill(*v),
                _ => return internal("whole-number load of another type"),
            },
            Op::LoadSF(d, src) => match scalar(cx, src) {
                Val::F(v) => regs.f[d as usize][..len].fill(*v),
                _ => return internal("real load of another type"),
            },
            Op::LoadSB(d, src) => match scalar(cx, src) {
                Val::B(v) => regs.b[d as usize][..len].fill(*v),
                _ => return internal("true/false load of another type"),
            },
            Op::LoadCI(d, src) => match column(cx, src) {
                Col::I(v) if v.len() >= end => regs.i[d as usize][..len].copy_from_slice(&v[start..end]),
                _ => return internal("whole-number column load"),
            },
            Op::LoadCF(d, src) => match column(cx, src) {
                Col::F(v) if v.len() >= end => regs.f[d as usize][..len].copy_from_slice(&v[start..end]),
                _ => return internal("real column load"),
            },
            Op::LoadCB(d, src) => match column(cx, src) {
                Col::B(v) if v.len() >= end => regs.b[d as usize][..len].copy_from_slice(&v[start..end]),
                _ => return internal("true/false column load"),
            },
            Op::LoadAggI(d, k) => match prepared.aggs[k as usize] {
                Val::I(v) => regs.i[d as usize][..len].fill(v),
                _ => return internal("aggregate type"),
            },
            Op::LoadAggF(d, k) => match prepared.aggs[k as usize] {
                Val::F(v) => regs.f[d as usize][..len].fill(v),
                _ => return internal("aggregate type"),
            },
            Op::NegI(d, a) => {
                let (d, a) = pick!(regs.i, len, d, a);
                let mut bad = false;
                for (d, a) in d.iter_mut().zip(a) {
                    let (v, o) = a.overflowing_neg();
                    *d = v;
                    bad |= o;
                }
                if bad {
                    return overflow();
                }
            }
            Op::NegF(d, a) => {
                let (d, a) = pick!(regs.f, len, d, a);
                for (d, a) in d.iter_mut().zip(a) {
                    *d = -*a;
                }
            }
            Op::NotB(d, a) => {
                let (d, a) = pick!(regs.b, len, d, a);
                for (d, a) in d.iter_mut().zip(a) {
                    *d = !*a;
                }
            }
            Op::AddI(d, a, b) | Op::SubI(d, a, b) | Op::MulI(d, a, b) => {
                let (d, a, b) = pick!(regs.i, len, d, a, b);
                let mut bad = false;
                for ((d, a), b) in d.iter_mut().zip(a).zip(b) {
                    let (v, o) = match op {
                        Op::AddI(..) => a.overflowing_add(*b),
                        Op::SubI(..) => a.overflowing_sub(*b),
                        _ => a.overflowing_mul(*b),
                    };
                    *d = v;
                    bad |= o;
                }
                if bad {
                    return overflow();
                }
            }
            Op::AddF(d, a, b) => {
                let (d, a, b) = pick!(regs.f, len, d, a, b);
                for ((d, a), b) in d.iter_mut().zip(a).zip(b) {
                    *d = *a + *b;
                }
            }
            Op::SubF(d, a, b) => {
                let (d, a, b) = pick!(regs.f, len, d, a, b);
                for ((d, a), b) in d.iter_mut().zip(a).zip(b) {
                    *d = *a - *b;
                }
            }
            Op::MulF(d, a, b) => {
                let (d, a, b) = pick!(regs.f, len, d, a, b);
                for ((d, a), b) in d.iter_mut().zip(a).zip(b) {
                    *d = *a * *b;
                }
            }
            Op::DivF(d, a, b) => {
                // IEEE 754 division: x/0 is an infinity or not-a-number, never a trap.
                let (d, a, b) = pick!(regs.f, len, d, a, b);
                for ((d, a), b) in d.iter_mut().zip(a).zip(b) {
                    *d = *a / *b;
                }
            }
            Op::IToF(d, a) => {
                for (d, a) in regs.f[d as usize][..len].iter_mut().zip(&regs.i[a as usize][..len]) {
                    *d = *a as f64;
                }
            }
            Op::CmpI(cmp, d, a, b) => {
                let (a, b) = (&regs.i[a as usize][..len], &regs.i[b as usize][..len]);
                for ((d, a), b) in regs.b[d as usize][..len].iter_mut().zip(a).zip(b) {
                    *d = compare(cmp, *a, *b);
                }
            }
            Op::CmpF(cmp, d, a, b) => {
                let (a, b) = (&regs.f[a as usize][..len], &regs.f[b as usize][..len]);
                for ((d, a), b) in regs.b[d as usize][..len].iter_mut().zip(a).zip(b) {
                    *d = compare(cmp, *a, *b);
                }
            }
            Op::CmpB(equal, d, a, b) => {
                let (d, a, b) = pick!(regs.b, len, d, a, b);
                for ((d, a), b) in d.iter_mut().zip(a).zip(b) {
                    *d = (*a == *b) == equal;
                }
            }
            Op::AndB(d, a, b) => {
                let (d, a, b) = pick!(regs.b, len, d, a, b);
                for ((d, a), b) in d.iter_mut().zip(a).zip(b) {
                    *d = *a && *b;
                }
            }
            Op::OrB(d, a, b) => {
                let (d, a, b) = pick!(regs.b, len, d, a, b);
                for ((d, a), b) in d.iter_mut().zip(a).zip(b) {
                    *d = *a || *b;
                }
            }
            // min(a, b) is b if b < a, else a; max(a, b) is b if b > a, else a.
            Op::MinI(d, a, b) => {
                let (d, a, b) = pick!(regs.i, len, d, a, b);
                for ((d, a), b) in d.iter_mut().zip(a).zip(b) {
                    *d = if *b < *a { *b } else { *a };
                }
            }
            Op::MaxI(d, a, b) => {
                let (d, a, b) = pick!(regs.i, len, d, a, b);
                for ((d, a), b) in d.iter_mut().zip(a).zip(b) {
                    *d = if *b > *a { *b } else { *a };
                }
            }
            Op::MinF(d, a, b) => {
                let (d, a, b) = pick!(regs.f, len, d, a, b);
                for ((d, a), b) in d.iter_mut().zip(a).zip(b) {
                    *d = if *b < *a { *b } else { *a };
                }
            }
            Op::MaxF(d, a, b) => {
                let (d, a, b) = pick!(regs.f, len, d, a, b);
                for ((d, a), b) in d.iter_mut().zip(a).zip(b) {
                    *d = if *b > *a { *b } else { *a };
                }
            }
            // clamp(x, lo, hi) is min(max(x, lo), hi) with the definitions above.
            Op::ClampI(d, x, lo, hi) => {
                let (d, x, lo, hi) = pick!(regs.i, len, d, x, lo, hi);
                for j in 0..len {
                    let m = if lo[j] > x[j] { lo[j] } else { x[j] };
                    d[j] = if hi[j] < m { hi[j] } else { m };
                }
            }
            Op::ClampF(d, x, lo, hi) => {
                let (d, x, lo, hi) = pick!(regs.f, len, d, x, lo, hi);
                for j in 0..len {
                    let m = if lo[j] > x[j] { lo[j] } else { x[j] };
                    d[j] = if hi[j] < m { hi[j] } else { m };
                }
            }
            Op::AbsI(d, a) => {
                let (d, a) = pick!(regs.i, len, d, a);
                let mut bad = false;
                for (d, a) in d.iter_mut().zip(a) {
                    let (v, o) = a.overflowing_abs();
                    *d = v;
                    bad |= o;
                }
                if bad {
                    return overflow();
                }
            }
            Op::AbsF(d, a) => {
                let (d, a) = pick!(regs.f, len, d, a);
                for (d, a) in d.iter_mut().zip(a) {
                    *d = a.abs();
                }
            }
            Op::ToInt(mode, d, a) => {
                for (d, a) in regs.i[d as usize][..len].iter_mut().zip(&regs.f[a as usize][..len]) {
                    *d = real_to_int(*a, mode)?;
                }
            }
            Op::SelI(d, c, a, b) => {
                let c = &regs.b[c as usize][..len];
                let (d, a, b) = pick!(regs.i, len, d, a, b);
                for j in 0..len {
                    d[j] = if c[j] { a[j] } else { b[j] };
                }
            }
            Op::SelF(d, c, a, b) => {
                let c = &regs.b[c as usize][..len];
                let (d, a, b) = pick!(regs.f, len, d, a, b);
                for j in 0..len {
                    d[j] = if c[j] { a[j] } else { b[j] };
                }
            }
            Op::SelB(d, c, a, b) => {
                let (d, c, a, b) = pick!(regs.b, len, d, c, a, b);
                for j in 0..len {
                    d[j] = if c[j] { a[j] } else { b[j] };
                }
            }
            Op::SafeDiv(d, a, b, fallback) => {
                let (d, a, b, fallback) = pick!(regs.f, len, d, a, b, fallback);
                for j in 0..len {
                    d[j] = if b[j] == 0.0 { fallback[j] } else { a[j] / b[j] };
                }
            }
            Op::MulDiv(d, a, b, c) => {
                let (d, a, b, c) = pick!(regs.i, len, d, a, b, c);
                for j in 0..len {
                    if c[j] <= 0 {
                        return Err("muldiv(): the divisor must be positive".to_string());
                    }
                    let quotient = (a[j] as i128 * b[j] as i128).div_euclid(c[j] as i128);
                    let Ok(quotient) = i64::try_from(quotient) else { return overflow() };
                    d[j] = quotient;
                }
            }
            Op::Marginal(d, x, k) => {
                let (lows, rates) = &prepared.tables[k as usize];
                let (d, x) = pick!(regs.i, len, d, x);
                for (d, x) in d.iter_mut().zip(x) {
                    *d = marginal_amount(*x, lows, rates)?;
                }
            }
            Op::Rand(d, stream, per_record) => {
                let d = &mut regs.f[d as usize][..len];
                match (per_record, entity) {
                    (true, Some(entity)) => {
                        let ids = &cx.entities[entity].ids[start..end];
                        for (d, id) in d.iter_mut().zip(ids) {
                            *d = uniform(cx.seed, stream, *id, cx.step);
                        }
                    }
                    (false, _) => d.fill(uniform(cx.seed, stream, 0, cx.step)),
                    (true, None) => return internal("per-record draw in a national formula"),
                }
            }
        }
    }
    Ok(())
}
