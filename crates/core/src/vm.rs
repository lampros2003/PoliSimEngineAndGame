//! The block-wise interpreter.
//!
//! Each instruction is applied to a block of records before the next instruction runs.
//! A national formula is the same thing with a block of one. Evaluation is strict (engine
//! contract, section 7): every instruction runs for every record, and an illegal result
//! anywhere fails the whole formula.

use crate::model::Entity;
use crate::program::{Agg, AggBy, AggKind, Cmp, Col, Hoisted, Op, Program, Rounding, Src, SubKind, Ty, Val};
use crate::rng::uniform;
use rayon::prelude::*;

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
    /// Each entity's current weights (format 1: they change when a weight state does).
    pub weights: &'a [Vec<i64>],
    pub seed: u64,
    /// Index of the step being computed.
    pub step: u32,
    /// Read one input from somewhere else. Used only to explain results, never to step.
    pub swap: Option<Swap<'a>>,
}

/// Replaces one input of a formula: reads of `sym` (through `prev()` when `lagged`) come
/// from these slices instead.
#[derive(Clone, Copy)]
pub struct Swap<'a> {
    pub sym: u32,
    pub lagged: bool,
    pub scal: &'a [Val],
    pub cols: &'a [Col],
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

    /// Stage S10: registers for `prog`, taken from this thread's spares when it has them
    /// (every instruction writes its register before any reads it, so old contents do not
    /// matter). Give them back with [`Regs::put`].
    fn take(prog: &Program, len: usize) -> Regs {
        let spare = SPARE.with(|s| s.borrow_mut().pop());
        let Some(mut regs) = spare else { return Regs::new(prog, len) };
        fn fit<T: Clone>(files: &mut Vec<Vec<T>>, count: usize, len: usize, zero: T) {
            files.truncate(count);
            files.resize_with(count, Vec::new);
            for file in files.iter_mut() {
                if file.len() < len {
                    file.resize(len, zero.clone());
                }
            }
        }
        fit(&mut regs.i, prog.n_i as usize, len, 0);
        fit(&mut regs.f, prog.n_f as usize, len, 0.0);
        fit(&mut regs.b, prog.n_b as usize, len, false);
        regs
    }

    fn put(self) {
        SPARE.with(|s| {
            let mut spare = s.borrow_mut();
            if spare.len() < 4 {
                spare.push(self);
            }
        });
    }
}

thread_local! {
    /// Stage S10: each thread's spare registers, kept between formulas.
    static SPARE: std::cell::RefCell<Vec<Regs>> = const { std::cell::RefCell::new(Vec::new()) };
}

/// Values a program needs before its instructions run: aggregates and table bands.
struct Prepared {
    aggs: Vec<Val>,
    tables: Vec<(Vec<i64>, Vec<f64>)>,
    /// Stage S11.1: each curve's points, (xs, ys).
    curves: Vec<(Vec<f64>, Vec<f64>)>,
    /// Format 1: each sub-program's result, one value per cell of this program's domain.
    subs: Vec<Col>,
    /// Format 1: each grouped aggregate, one value per member of its dimension.
    aggs_by: Vec<Col>,
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
    let mut curves = Vec::with_capacity(prog.curves.len());
    for curve in &prog.curves {
        let mut axes = [Vec::with_capacity(curve.lows.len()), Vec::with_capacity(curve.rates.len())];
        for (axis, programs) in axes.iter_mut().zip([&curve.lows, &curve.rates]) {
            for point in programs {
                match eval_scalar(point, cx)? {
                    Val::F(v) => axis.push(v),
                    _ => return internal("a curve's point is not a real"),
                }
            }
        }
        let [xs, ys] = axes;
        curves.push((xs, ys));
    }
    let mut aggs = Vec::with_capacity(prog.aggs.len());
    for agg in &prog.aggs {
        aggs.push(eval_agg(agg, cx)?);
    }
    let mut subs = Vec::with_capacity(prog.subs.len());
    for sub in &prog.subs {
        let column = eval_cells(&sub.prog, sub.cells, cx)?;
        subs.push(match (&sub.by, sub.kind) {
            (Some(by), SubKind::SumBy { group }) => {
                let keys = eval_cells(&by.key, sub.cells, cx)?;
                finish_sum_by(column, keys, group, by)?
            }
            _ => finish_sub(sub.kind, column)?,
        });
    }
    let mut aggs_by = Vec::with_capacity(prog.aggs_by.len());
    for agg in &prog.aggs_by {
        aggs_by.push(eval_agg_by(agg, cx)?);
    }
    Ok(Prepared { aggs, tables, curves, subs, aggs_by })
}

/// `wsum_by` and `wcount_by`: like `wsum` and `wcount`, but each record's term goes to the
/// member its key names, in ascending record order within each member.
///
/// Stage S10: the terms and keys are computed on several threads, then added in record
/// order on one, so the sums are the same bits. Errors come in the order the blocks would
/// give them one after another: in each block, the term's error, then the key's, then a
/// key that names no member or a whole-number sum that overflows.
fn eval_agg_by(agg: &AggBy, cx: &EvalCtx) -> Check<Col> {
    let value_prepared = prepare(&agg.value, cx)?;
    let key_prepared = prepare(&agg.key, cx)?;
    let weights = &cx.weights[agg.entity];
    let count = weights.len();
    let (values, keys) = rayon::join(
        || eval_all(&agg.value, cx, Some(agg.entity), count, &value_prepared),
        || eval_all(&agg.key, cx, Some(agg.entity), count, &key_prepared),
    );
    let (values, value_failure) = split(values);
    let (keys, key_failure) = split(keys);
    // Records before the first block that failed to evaluate, if any.
    let stop = [&value_failure, &key_failure].iter().filter_map(|f| f.as_ref().map(|f| f.0)).min().unwrap_or(count);
    let Col::I(keys) = keys else { return internal("a key that is not a whole number") };
    let mut whole = vec![0i128; agg.size];
    let mut real = vec![0.0f64; agg.size];
    for (k, &key) in keys.iter().enumerate().take(stop) {
        let pos = key.checked_sub(agg.first).filter(|p| (0..agg.size as i64).contains(p));
        let Some(pos) = pos else {
            return Err(format!("{}(): a record's key {key} is not a member of {}", agg.name, agg.dim));
        };
        let (pos, w) = (pos as usize, weights[k]);
        match (&agg.kind, &values) {
            (AggKind::SumInt, Col::I(v)) => match whole[pos].checked_add(w as i128 * v[k] as i128) {
                Some(total) => whole[pos] = total,
                None => return overflow(),
            },
            (AggKind::SumReal, Col::F(v)) => real[pos] += w as f64 * v[k],
            (AggKind::Count, Col::B(v)) => {
                if v[k] {
                    whole[pos] += w as i128;
                }
            }
            _ => return internal("a grouped sum's term of another type"),
        }
    }
    match (value_failure, key_failure) {
        (Some((at, e)), _) if at == stop => return Err(e),
        (_, Some((_, e))) if stop < count => return Err(e),
        _ => {}
    }
    match agg.kind {
        AggKind::SumReal => Ok(Col::F(real)),
        _ => {
            let mut out = Vec::with_capacity(agg.size);
            for total in whole {
                match i64::try_from(total) {
                    Ok(t) => out.push(t),
                    Err(_) => return overflow(),
                }
            }
            Ok(Col::I(out))
        }
    }
}

/// Stage S10: a value for each record or cell `0..count`, from blocks evaluated on several
/// threads when there are enough of them, joined in order. On failure: the start of the
/// first block that failed, its error, and the values of the records before it.
type Partial = Result<Col, (usize, String, Col)>;

fn empty(ty: Ty, capacity: usize) -> Col {
    match ty {
        Ty::Int => Col::I(Vec::with_capacity(capacity)),
        Ty::Real => Col::F(Vec::with_capacity(capacity)),
        Ty::Bool => Col::B(Vec::with_capacity(capacity)),
    }
}

fn append(out: &mut Col, part: &Col) {
    match (out, part) {
        (Col::I(v), Col::I(p)) => v.extend_from_slice(p),
        (Col::F(v), Col::F(p)) => v.extend_from_slice(p),
        (Col::B(v), Col::B(p)) => v.extend_from_slice(p),
        _ => unreachable!("every part has the program's type"),
    }
}

/// The values computed, and the failure (where, what) if there was one.
fn split(result: Partial) -> (Col, Option<(usize, String)>) {
    match result {
        Ok(col) => (col, None),
        Err((at, e, before)) => (before, Some((at, e))),
    }
}

/// Stage S10.8: what a hoisted program's `once` part computed, one value for each of its
/// `fills`.
type Once<'p> = Option<(&'p Hoisted, Vec<Val>)>;

/// Stage S10.8: runs the part of `prog` that is the same for every record or cell, once.
/// `None` when the program is not split, there is nothing to compute, or that part fails:
/// the whole program then runs block by block, and gives its error exactly as before.
fn run_once<'p>(prog: &'p Program, cx: &EvalCtx, count: usize, prepared: &Prepared) -> Once<'p> {
    let hoisted = prog.hoisted.as_deref()?;
    if count == 0 {
        return None;
    }
    let mut regs = Regs::take(prog, 1);
    let ran = run_block(prog, &hoisted.once, cx, None, 0, 1, &mut regs, prepared);
    let values = ran.ok().map(|()| {
        hoisted
            .fills
            .iter()
            .map(|&(ty, r)| match ty {
                Ty::Int => Val::I(regs.i[r as usize][0]),
                Ty::Real => Val::F(regs.f[r as usize][0]),
                Ty::Bool => Val::B(regs.b[r as usize][0]),
            })
            .collect()
    });
    regs.put();
    values.map(|v| (hoisted, v))
}

fn eval_all(prog: &Program, cx: &EvalCtx, entity: Option<usize>, count: usize, prepared: &Prepared) -> Partial {
    let task = BLOCK * TASK_BLOCKS;
    let once = run_once(prog, cx, count, prepared);
    let once = once.as_ref().map(|(h, v)| (*h, v.as_slice()));
    if count <= task {
        return eval_range(prog, cx, entity, 0, count, prepared, once);
    }
    // Records (and cells) are independent, so tasks of whole blocks run on several threads
    // and give what one thread would; the parts are joined in order, and the first failure
    // in order is the one reported, as if the blocks had run one after another.
    if let Some(out) = eval_into(prog, cx, entity, count, prepared, once, task) {
        return Ok(out);
    }
    // Something failed: run again in parts, to report the first failure in order with the
    // values before it.
    let starts: Vec<usize> = (0..count).step_by(task).collect();
    let parts: Vec<Partial> =
        starts.par_iter().map(|&s| eval_range(prog, cx, entity, s, (s + task).min(count), prepared, once)).collect();
    let mut out = empty(prog.ty, count);
    for part in parts {
        match part {
            Ok(col) => append(&mut out, &col),
            Err((at, e, before)) => {
                append(&mut out, &before);
                return Err((at, e, out));
            }
        }
    }
    Ok(out)
}

/// Stage S14.3: every record or cell, tasks of `task` written straight into one column
/// (no parts to join). `None` if any task failed.
fn eval_into(
    prog: &Program,
    cx: &EvalCtx,
    entity: Option<usize>,
    count: usize,
    prepared: &Prepared,
    once: Option<(&Hoisted, &[Val])>,
    task: usize,
) -> Option<Col> {
    fn fill<T: Copy + Send>(
        out: &mut [T],
        task: usize,
        register: impl Fn(&Regs, usize) -> &[T] + Sync,
        run: impl Fn(usize, usize, &mut dyn FnMut(&Regs, usize)) -> bool + Sync,
    ) -> bool {
        out.par_chunks_mut(task).enumerate().all(|(k, chunk)| {
            let mut at = 0;
            run(k * task, chunk.len(), &mut |regs, len| {
                chunk[at..at + len].copy_from_slice(&register(regs, len)[..len]);
                at += len;
            })
        })
    }
    let r = prog.result as usize;
    let run = |start: usize, len: usize, sink: &mut dyn FnMut(&Regs, usize)| {
        run_range(prog, cx, entity, start, start + len, prepared, once, sink).is_ok()
    };
    match prog.ty {
        Ty::Int => {
            let mut out = vec![0i64; count];
            fill(&mut out, task, |regs, _| &regs.i[r], run).then_some(Col::I(out))
        }
        Ty::Real => {
            let mut out = vec![0.0f64; count];
            fill(&mut out, task, |regs, _| &regs.f[r], run).then_some(Col::F(out))
        }
        Ty::Bool => {
            let mut out = vec![false; count];
            fill(&mut out, task, |regs, _| &regs.b[r], run).then_some(Col::B(out))
        }
    }
}

/// Format 1: evaluates a formula with dimensions for every cell of its domain, in row-major
/// order (stage S10: on several threads when there are many cells).
pub fn eval_cells(prog: &Program, cells: usize, cx: &EvalCtx) -> Check<Col> {
    let prepared = prepare(prog, cx)?;
    eval_all(prog, cx, None, cells, &prepared).map_err(|(_, e, _)| e)
}

/// Stage S10.3: `sum_by`. Each run of `group` cells goes, cell by cell in order, to the
/// result's cell its key names; whole numbers are added exactly and checked once, reals one
/// at a time from 0.0, so each result cell adds its terms in ascending order of the summed
/// dimension.
fn finish_sum_by(values: Col, keys: Col, group: usize, by: &crate::program::SumBy) -> Check<Col> {
    let Col::I(keys) = keys else { return internal("a key that is not a whole number") };
    let position = |k: i64| -> Check<usize> {
        match k.checked_sub(by.first) {
            Some(p) if (0..by.size as i64).contains(&p) => Ok(p as usize),
            _ => Err(format!("sum_by(): a key {k} is not a member of {}", by.dim)),
        }
    };
    match values {
        Col::I(v) => {
            let mut acc = vec![0i128; by.cells];
            for (run, &base) in by.bases.iter().enumerate() {
                for j in 0..group {
                    let at = run * group + j;
                    acc[base as usize + by.stride * position(keys[at])?] += v[at] as i128;
                }
            }
            let mut out = Vec::with_capacity(by.cells);
            for total in acc {
                match i64::try_from(total) {
                    Ok(t) => out.push(t),
                    Err(_) => return overflow(),
                }
            }
            Ok(Col::I(out))
        }
        Col::F(v) => {
            let mut acc = vec![0.0f64; by.cells];
            for (run, &base) in by.bases.iter().enumerate() {
                for j in 0..group {
                    let at = run * group + j;
                    let cell = base as usize + by.stride * position(keys[at])?;
                    acc[cell] += v[at];
                }
            }
            Ok(Col::F(acc))
        }
        Col::B(_) => internal("sum_by of true/false values"),
    }
}

/// `sum`: runs of `group` cells added one at a time from 0 (whole numbers exactly, only the
/// total checked) or 0.0. `cohort_shift`: everything one member up along a dimension, the
/// first member zero and the last keeping its own plus the one below.
fn finish_sub(kind: SubKind, column: Col) -> Check<Col> {
    match kind {
        SubKind::Sum { group } => match column {
            Col::I(v) => {
                let mut out = Vec::with_capacity(v.len() / group.max(1));
                for run in v.chunks(group) {
                    let total: i128 = run.iter().map(|x| *x as i128).sum();
                    match i64::try_from(total) {
                        Ok(t) => out.push(t),
                        Err(_) => return overflow(),
                    }
                }
                Ok(Col::I(out))
            }
            Col::F(v) => Ok(Col::F(
                v.chunks(group)
                    .map(|run| {
                        let mut acc = 0.0f64;
                        for x in run {
                            acc += *x;
                        }
                        acc
                    })
                    .collect(),
            )),
            Col::B(_) => internal("sum of true/false values"),
        },
        SubKind::SumBy { .. } => internal("sum_by without its key"),
        SubKind::Largest { group } | SubKind::Smallest { group } => {
            let largest = matches!(kind, SubKind::Largest { .. });
            match column {
                Col::I(v) => Ok(Col::I(
                    v.chunks(group)
                        .map(|run| {
                            run[1..].iter().fold(run[0], |best, &y| {
                                if (largest && y > best) || (!largest && y < best) { y } else { best }
                            })
                        })
                        .collect(),
                )),
                Col::F(v) => Ok(Col::F(
                    v.chunks(group)
                        .map(|run| {
                            run[1..].iter().fold(run[0], |best, &y| {
                                if (largest && y > best) || (!largest && y < best) { y } else { best }
                            })
                        })
                        .collect(),
                )),
                Col::B(_) => internal("largest or smallest of true/false values"),
            }
        }
        SubKind::Shift { stride, size } => {
            let at = |c: usize| (c / stride) % size;
            match column {
                Col::I(v) => {
                    let mut out = Vec::with_capacity(v.len());
                    for c in 0..v.len() {
                        let p = at(c);
                        out.push(if size == 1 {
                            v[c]
                        } else if p == 0 {
                            0
                        } else if p == size - 1 {
                            match v[c - stride].checked_add(v[c]) {
                                Some(total) => total,
                                None => return overflow(),
                            }
                        } else {
                            v[c - stride]
                        });
                    }
                    Ok(Col::I(out))
                }
                Col::F(v) => Ok(Col::F(
                    (0..v.len())
                        .map(|c| {
                            let p = at(c);
                            if size == 1 {
                                v[c]
                            } else if p == 0 {
                                0.0
                            } else if p == size - 1 {
                                v[c - stride] + v[c]
                            } else {
                                v[c - stride]
                            }
                        })
                        .collect(),
                )),
                Col::B(_) => internal("cohort_shift of true/false values"),
            }
        }
    }
}

/// Evaluates a national formula.
pub fn eval_scalar(prog: &Program, cx: &EvalCtx) -> Check<Val> {
    let prepared = prepare(prog, cx)?;
    let mut regs = Regs::take(prog, 1);
    let ran = run_block(prog, &prog.ops, cx, None, 0, 1, &mut regs, &prepared);
    let r = prog.result as usize;
    let value = match prog.ty {
        Ty::Int => Val::I(regs.i[r][0]),
        Ty::Real => Val::F(regs.f[r][0]),
        Ty::Bool => Val::B(regs.b[r][0]),
    };
    regs.put();
    ran.map(|()| value)
}

/// Evaluates a per-record formula for every record of `entity`.
pub fn eval_column(prog: &Program, entity: usize, cx: &EvalCtx) -> Check<Col> {
    let prepared = prepare(prog, cx)?;
    let count = cx.entities[entity].ids.len();
    eval_all(prog, cx, Some(entity), count, &prepared).map_err(|(_, e, _)| e)
}

/// Blocks per parallel task (4,096 records): smaller sets of records run on one thread.
const TASK_BLOCKS: usize = 16;

/// Records (or cells) `start..end`, block after block: the whole program, or (stage S10.8)
/// the part of a hoisted one that differs between records, after filling the registers it
/// reads from the part computed once.
fn eval_range(
    prog: &Program,
    cx: &EvalCtx,
    entity: Option<usize>,
    start: usize,
    end: usize,
    prepared: &Prepared,
    once: Option<(&Hoisted, &[Val])>,
) -> Partial {
    let r = prog.result as usize;
    let mut out = empty(prog.ty, end - start);
    let ran = run_range(prog, cx, entity, start, end, prepared, once, &mut |regs, len| match &mut out {
        Col::I(v) => v.extend_from_slice(&regs.i[r][..len]),
        Col::F(v) => v.extend_from_slice(&regs.f[r][..len]),
        Col::B(v) => v.extend_from_slice(&regs.b[r][..len]),
    });
    match ran {
        Ok(()) => Ok(out),
        Err((at, e)) => Err((at, e, out)),
    }
}

/// Records (or cells) `start..end`, block after block, each block's registers handed to
/// `sink` with its length. On failure: where the failing block starts, and why.
#[allow(clippy::too_many_arguments)]
fn run_range(
    prog: &Program,
    cx: &EvalCtx,
    entity: Option<usize>,
    start: usize,
    end: usize,
    prepared: &Prepared,
    once: Option<(&Hoisted, &[Val])>,
    sink: &mut dyn FnMut(&Regs, usize),
) -> Result<(), (usize, String)> {
    let count = end - start;
    let mut regs = Regs::take(prog, BLOCK.min(count.max(1)));
    let mut at = start;
    let ops = once.map_or(prog.ops.as_slice(), |(h, _)| h.each.as_slice());
    while at < end {
        let len = BLOCK.min(end - at);
        if let Some((hoisted, values)) = once {
            for (&(_, reg), value) in hoisted.fills.iter().zip(values) {
                match *value {
                    Val::I(v) => regs.i[reg as usize][..len].fill(v),
                    Val::F(v) => regs.f[reg as usize][..len].fill(v),
                    Val::B(v) => regs.b[reg as usize][..len].fill(v),
                }
            }
        }
        if let Err(e) = run_block(prog, ops, cx, entity, at, len, &mut regs, prepared) {
            regs.put();
            return Err((at, e));
        }
        sink(&regs, len);
        at += len;
    }
    regs.put();
    Ok(())
}

/// `wsum` and `wcount`. Whole-number sums are exact; a real sum is accumulated in
/// ascending record order, each term being `real(weight) * value`. Stage S10: the terms are
/// computed on several threads and added on one, so the sum is the same bits; a sum that
/// overflows before the first block that fails is reported first, as one thread would.
/// Stage S10.9: `quantile`. The share, then the checks (a share from 0 to 1, no value that
/// is not a number, weights that add to something), then the records with a weight in
/// order of value (ties by record order): the value of the first at which the weight so
/// far reaches the share of the total.
fn quantile(agg: &Agg, terms: &Col, weights: &[i64], counts: Option<&[i64]>, cx: &EvalCtx) -> Check<Val> {
    let Some(share) = &agg.share else { return internal("a quantile without its share") };
    let p = match eval_scalar(share, cx)? {
        Val::F(p) => p,
        _ => return internal("a quantile's share is not a real"),
    };
    if !(0.0..=1.0).contains(&p) {
        return Err("quantile(): the share must be from 0 to 1".to_string());
    }
    if let Col::F(v) = terms {
        if v.iter().any(|x| x.is_nan()) {
            return Err("quantile(): a record's value is not a number".to_string());
        }
    }
    if counts.is_some_and(|c| c.iter().any(|n| *n < 0)) {
        return Err("quantile(): a record's count is below zero".to_string());
    }
    let each: Vec<i128> = match counts {
        Some(c) => weights.iter().zip(c).map(|(w, n)| *w as i128 * *n as i128).collect(),
        None => weights.iter().map(|w| *w as i128).collect(),
    };
    let total: i128 = each.iter().sum();
    if total <= 0 {
        return Err("quantile(): the records' weights add to nothing".to_string());
    }
    let target = p * total as f64;
    // Stage S11.5: each value as a whole-number key in the same order (for a real, -0.0
    // first becomes 0.0, so the two tie, then by record, as the spec has them; no value is
    // not-a-number), paired with its record. No two pairs are equal, so the record the spec's
    // walk stops at is the one `weighted_select` finds; the value is read from the record,
    // so its sign is kept.
    let mut pairs: Vec<(u64, u32)> = match terms {
        Col::I(v) => {
            (0..weights.len()).filter(|r| each[*r] != 0).map(|r| ((v[r] as u64) ^ (1 << 63), r as u32)).collect()
        }
        Col::F(v) => {
            let key = |x: f64| {
                let bits = (x + 0.0).to_bits();
                if bits >> 63 == 1 { !bits } else { bits | (1 << 63) }
            };
            (0..weights.len()).filter(|r| each[*r] != 0).map(|r| (key(v[r]), r as u32)).collect()
        }
        Col::B(_) => return internal("a quantile of true/false values"),
    };
    let Some(r) = weighted_select(&mut pairs, &each, target) else {
        return internal("a quantile past its records");
    };
    let r = r as usize;
    Ok(match terms {
        Col::I(v) => Val::I(v[r]),
        Col::F(v) => Val::F(v[r]),
        Col::B(_) => unreachable!("checked above"),
    })
}

/// Stage S11.5: of `pairs` (distinct keys with their records), the record at which the
/// weight so far, in ascending order of key, first reaches `target` (compared as a real),
/// as walking the sorted pairs would find it, without sorting them all: each round splits
/// the pairs around the middle one and keeps the side the answer is on.
fn weighted_select(pairs: &mut [(u64, u32)], each: &[i128], target: f64) -> Option<u32> {
    let (mut lo, mut hi) = (0usize, pairs.len());
    let mut below: i128 = 0;
    while hi - lo > 32 {
        let mid = lo + (hi - lo) / 2;
        pairs[lo..hi].select_nth_unstable(mid - lo);
        let left: i128 = pairs[lo..mid].iter().map(|(_, r)| each[*r as usize]).sum();
        let pivot = each[pairs[mid].1 as usize];
        if (below + left) as f64 >= target {
            hi = mid;
        } else if (below + left + pivot) as f64 >= target {
            return Some(pairs[mid].1);
        } else {
            below += left + pivot;
            lo = mid + 1;
        }
    }
    pairs[lo..hi].sort_unstable();
    for &(_, r) in &pairs[lo..hi] {
        below += each[r as usize];
        if below as f64 >= target {
            return Some(r);
        }
    }
    None
}

fn eval_agg(agg: &Agg, cx: &EvalCtx) -> Check<Val> {
    let prog = &agg.prog;
    let prepared = prepare(prog, cx)?;
    let weights = &cx.weights[agg.entity];
    let count = weights.len();
    let (terms, failure) = split(eval_all(prog, cx, Some(agg.entity), count, &prepared));
    if matches!(agg.kind, AggKind::Quantile) {
        if let Some((_, e)) = failure {
            return Err(e);
        }
        // Stage S11.2: each record's count, then its weight times its count.
        let counts = match &agg.times {
            Some(times) => {
                let prepared = prepare(times, cx)?;
                match eval_all(times, cx, Some(agg.entity), count, &prepared) {
                    Ok(Col::I(v)) => Some(v),
                    Ok(_) => return internal("a quantile's count is not a whole number"),
                    Err((_, e, _)) => return Err(e),
                }
            }
            None => None,
        };
        return quantile(agg, &terms, weights, counts.as_deref(), cx);
    }
    let mut whole: i128 = 0;
    let mut real: f64 = 0.0;
    match (&agg.kind, &terms) {
        (AggKind::SumInt, Col::I(v)) => {
            for (w, v) in weights.iter().zip(v) {
                whole = match whole.checked_add(*w as i128 * *v as i128) {
                    Some(total) => total,
                    None => return overflow(),
                };
            }
        }
        (AggKind::SumReal, Col::F(v)) => {
            for (w, v) in weights.iter().zip(v) {
                real += *w as f64 * *v;
            }
        }
        (AggKind::Count, Col::B(v)) => {
            for (w, c) in weights.iter().zip(v) {
                if *c {
                    whole += *w as i128;
                }
            }
        }
        _ => return internal("a sum's term of another type"),
    }
    if let Some((_, e)) = failure {
        return Err(e);
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

/// Stage S11.1: a curve through the points (xs[k], ys[k]), xs strictly ascending (checked by
/// the caller), as docs/spec/02 defines it.
pub fn curve_value(x: f64, xs: &[f64], ys: &[f64]) -> f64 {
    let last = xs.len() - 1;
    if x.is_nan() {
        return x;
    }
    if x <= xs[0] {
        return ys[0];
    }
    if x >= xs[last] {
        return ys[last];
    }
    let mut k = 0;
    // x is a number and the points ascend, so this is "x is not below the next point".
    while x >= xs[k + 1] {
        k += 1;
    }
    ys[k] + (ys[k + 1] - ys[k]) * ((x - xs[k]) / (xs[k + 1] - xs[k]))
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
    if let Some(swap) = cx.swap.filter(|s| s.sym == src.sym && s.lagged == src.lagged) {
        return &swap.scal[src.sym as usize];
    }
    if src.lagged { &cx.prev_scal[src.sym as usize] } else { &cx.scal[src.sym as usize] }
}

fn column<'a>(cx: &'a EvalCtx, src: Src) -> &'a Col {
    if let Some(swap) = cx.swap.filter(|s| s.sym == src.sym && s.lagged == src.lagged) {
        return &swap.cols[src.sym as usize];
    }
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

#[allow(clippy::too_many_arguments)]
fn run_block(
    prog: &Program,
    ops: &[Op],
    cx: &EvalCtx,
    entity: Option<usize>,
    start: usize,
    len: usize,
    regs: &mut Regs,
    prepared: &Prepared,
) -> Check<()> {
    let end = start + len;
    for op in ops {
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
            Op::LoadGI(d, src, g) => {
                let map = &prog.gathers[g as usize][start..end];
                let Col::I(v) = column(cx, src) else { return internal("whole-number gather") };
                for (d, m) in regs.i[d as usize][..len].iter_mut().zip(map) {
                    *d = v[*m as usize];
                }
            }
            Op::LoadGF(d, src, g) => {
                let map = &prog.gathers[g as usize][start..end];
                let Col::F(v) = column(cx, src) else { return internal("real gather") };
                for (d, m) in regs.f[d as usize][..len].iter_mut().zip(map) {
                    *d = v[*m as usize];
                }
            }
            Op::LoadGB(d, src, g) => {
                let map = &prog.gathers[g as usize][start..end];
                let Col::B(v) = column(cx, src) else { return internal("true/false gather") };
                for (d, m) in regs.b[d as usize][..len].iter_mut().zip(map) {
                    *d = v[*m as usize];
                }
            }
            Op::Coord(d, c) => regs.i[d as usize][..len].copy_from_slice(&prog.coords[c as usize][start..end]),
            Op::IndexI(d, u) | Op::IndexF(d, u) | Op::IndexB(d, u) => {
                let usage = &prog.indexes[u as usize];
                let mut flats = vec![0usize; len];
                if !usage.base.is_empty() {
                    for (f, b) in flats.iter_mut().zip(&usage.base[start..end]) {
                        *f = *b as usize;
                    }
                }
                for fixed in &usage.fixed {
                    let coords = &regs.i[fixed.reg as usize][..len];
                    for (f, v) in flats.iter_mut().zip(coords) {
                        let pos = v.checked_sub(fixed.first).filter(|p| (0..fixed.size as i64).contains(p));
                        let Some(pos) = pos else {
                            return Err(format!(
                                "{}[{}: {v}]: {} has no such member",
                                usage.name, fixed.dim, fixed.dim
                            ));
                        };
                        *f += pos as usize * fixed.stride as usize;
                    }
                }
                match (op, column(cx, usage.src)) {
                    (Op::IndexI(..), Col::I(v)) => {
                        for (d, f) in regs.i[d as usize][..len].iter_mut().zip(&flats) {
                            *d = v[*f];
                        }
                    }
                    (Op::IndexF(..), Col::F(v)) => {
                        for (d, f) in regs.f[d as usize][..len].iter_mut().zip(&flats) {
                            *d = v[*f];
                        }
                    }
                    (Op::IndexB(..), Col::B(v)) => {
                        for (d, f) in regs.b[d as usize][..len].iter_mut().zip(&flats) {
                            *d = v[*f];
                        }
                    }
                    _ => return internal("index of another type"),
                }
            }
            Op::LoadAggByI(d, k, g) => {
                let map = &prog.gathers[g as usize][start..end];
                let Col::I(v) = &prepared.aggs_by[k as usize] else { return internal("grouped aggregate type") };
                for (d, m) in regs.i[d as usize][..len].iter_mut().zip(map) {
                    *d = v[*m as usize];
                }
            }
            Op::LoadAggByF(d, k, g) => {
                let map = &prog.gathers[g as usize][start..end];
                let Col::F(v) = &prepared.aggs_by[k as usize] else { return internal("grouped aggregate type") };
                for (d, m) in regs.f[d as usize][..len].iter_mut().zip(map) {
                    *d = v[*m as usize];
                }
            }
            Op::LoadSubI(d, k) => match &prepared.subs[k as usize] {
                Col::I(v) => regs.i[d as usize][..len].copy_from_slice(&v[start..end]),
                _ => return internal("sub-program type"),
            },
            Op::LoadSubF(d, k) => match &prepared.subs[k as usize] {
                Col::F(v) => regs.f[d as usize][..len].copy_from_slice(&v[start..end]),
                _ => return internal("sub-program type"),
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
            Op::Exp(d, a) => {
                let (d, a) = pick!(regs.f, len, d, a);
                for (d, a) in d.iter_mut().zip(a) {
                    *d = crate::program::exp_fixed(*a);
                }
            }
            Op::Ln(d, a) => {
                let (d, a) = pick!(regs.f, len, d, a);
                for (d, a) in d.iter_mut().zip(a) {
                    *d = crate::program::ln_fixed(*a);
                }
            }
            Op::Sqrt(d, a) => {
                let (d, a) = pick!(regs.f, len, d, a);
                for (d, a) in d.iter_mut().zip(a) {
                    *d = crate::program::sqrt_fixed(*a);
                }
            }
            Op::Pow(d, a, b) => {
                let (d, a, b) = pick!(regs.f, len, d, a, b);
                for ((d, a), b) in d.iter_mut().zip(a).zip(b) {
                    *d = crate::program::pow_fixed(*a, *b);
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
            Op::DivI(d, a, b) | Op::ModI(d, a, b) => {
                let div = matches!(op, Op::DivI(..));
                let (d, a, b) = pick!(regs.i, len, d, a, b);
                for j in 0..len {
                    if b[j] <= 0 {
                        let name = if div { "div" } else { "mod" };
                        return Err(format!("{name}(): the divisor must be positive"));
                    }
                    // With a positive divisor floor division is Euclid's, and cannot overflow.
                    d[j] = if div { a[j].div_euclid(b[j]) } else { a[j].rem_euclid(b[j]) };
                }
            }
            Op::Marginal(d, x, k) => {
                let (lows, rates) = &prepared.tables[k as usize];
                let (d, x) = pick!(regs.i, len, d, x);
                for (d, x) in d.iter_mut().zip(x) {
                    *d = marginal_amount(*x, lows, rates)?;
                }
            }
            Op::Curve(d, x, k) => {
                let (xs, ys) = &prepared.curves[k as usize];
                // A point that is not a number fails too.
                if xs.windows(2).any(|w| w[0].partial_cmp(&w[1]) != Some(std::cmp::Ordering::Less)) {
                    return Err("curve(): a curve's points must have ascending x".to_string());
                }
                let (d, x) = pick!(regs.f, len, d, x);
                for (d, x) in d.iter_mut().zip(x) {
                    *d = curve_value(*x, xs, ys);
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
