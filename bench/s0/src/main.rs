//! Stage S0 micro-benchmarks. No dependencies; run with `cargo run --release`.
//!
//! Part A times the kinds of pass a monthly step makes over a million person records
//! held as plain columns. Part B times one household rule set three ways (hand-written
//! Rust, a bytecode interpreter that works on blocks of records, and the same bytecode
//! run one record at a time) at three rule depths. The question behind part B is
//! whether moddable formulas can be fast enough without a just-in-time compiler.
//!
//! Everything is single-threaded and integer arithmetic wraps (no overflow checks).
//! All three part-B variants must produce the same checksum.

use std::hint::black_box;
use std::time::Instant;

// ------------------------------------------------------------------ Philox4x32-10

const M0: u32 = 0xD251_1F53;
const M1: u32 = 0xCD9E_8D57;
const W0: u32 = 0x9E37_79B9;
const W1: u32 = 0xBB67_AE85;

#[inline(always)]
fn philox4x32_10(mut c: [u32; 4], mut k: [u32; 2]) -> [u32; 4] {
    for round in 0..10 {
        if round > 0 {
            k[0] = k[0].wrapping_add(W0);
            k[1] = k[1].wrapping_add(W1);
        }
        let p0 = (M0 as u64) * (c[0] as u64);
        let p1 = (M1 as u64) * (c[2] as u64);
        c = [(p1 >> 32) as u32 ^ c[1] ^ k[0], p1 as u32, (p0 >> 32) as u32 ^ c[3] ^ k[1], p0 as u32];
    }
    c
}

/// A real in [0, 1) keyed by (seed, stream, entity, step). Same definition as the engine's
/// (`crates/core/src/rng.rs`, and the retired Python reference's before it).
#[inline(always)]
fn uniform(seed: u64, stream: u32, entity: u64, step: u32) -> f64 {
    let o = philox4x32_10([entity as u32, (entity >> 32) as u32, step, stream], [seed as u32, (seed >> 32) as u32]);
    let bits = ((o[0] as u64) << 32) | o[1] as u64;
    (bits >> 11) as f64 * (1.0 / 9_007_199_254_740_992.0)
}

/// floor(a * b / c) for c > 0, exact. Takes the 64-bit path when the product fits.
#[inline(always)]
fn muldiv(a: i64, b: i64, c: i64) -> i64 {
    match a.checked_mul(b) {
        Some(p) => p.div_euclid(c),
        None => (a as i128 * b as i128).div_euclid(c as i128) as i64,
    }
}

// ------------------------------------------------------------------ data

struct Columns {
    n: usize,
    age_months: Vec<u16>,
    region: Vec<u8>,
    employed: Vec<i64>, // 0 or 1
    wage: Vec<i64>,     // pence per month
    equity: Vec<i64>,
    money: Vec<i64>,
    weight: Vec<i64>,
    opinion: [Vec<f64>; 4],
}

fn make_columns(n: usize) -> Columns {
    let mut c = Columns {
        n,
        age_months: vec![0; n],
        region: vec![0; n],
        employed: vec![0; n],
        wage: vec![0; n],
        equity: vec![0; n],
        money: vec![0; n],
        weight: vec![0; n],
        opinion: [vec![0.0; n], vec![0.0; n], vec![0.0; n], vec![0.0; n]],
    };
    for i in 0..n {
        let u = |stream: u32| uniform(42, stream, i as u64, 0);
        c.wage[i] = 90_000 + (u(10) * u(11) * 1_400_000.0) as i64;
        c.employed[i] = (u(12) < 0.94) as i64;
        c.equity[i] = if u(13) < 0.45 { 0 } else { (u(14) * u(14) * 800.0) as i64 };
        c.money[i] = c.wage[i] * 245 / 100;
        c.weight[i] = 600 + (u(15) * 800.0) as i64;
        c.age_months[i] = (u(16) * 1080.0) as u16;
        c.region[i] = (u(17) * 12.0) as u8;
        for (axis, column) in c.opinion.iter_mut().enumerate() {
            column[i] = u(20 + axis as u32) * 2.0 - 1.0;
        }
    }
    c
}

/// Policy and behaviour constants of the toy model, in pence and plain rates.
struct Params {
    allowance: i64,
    higher: i64,
    basic_rate: f64,
    higher_rate: f64,
    benefit: i64,
    a1: f64,
    a2: f64,
    pool: i64,
    total_equity: i64,
}

/// One synthetic means-tested instrument: a payment that tapers away with income.
#[derive(Clone, Copy)]
struct Instrument {
    threshold: i64,
    taper: f64,
    base: f64,
    cap: i64,
    flag: i64, // paid to households whose employed flag equals this
}

fn make_instruments(k: usize) -> Vec<Instrument> {
    (0..k)
        .map(|j| {
            let u = |stream: u32| uniform(7, stream, j as u64, 0);
            Instrument {
                threshold: 80_000 + (u(1) * 500_000.0) as i64,
                taper: 0.05 + u(2) * 0.6,
                base: 2_000.0 + u(3) * 30_000.0,
                cap: 5_000 + (u(4) * 20_000.0) as i64,
                flag: (u(5) < 0.5) as i64,
            }
        })
        .collect()
}

// ------------------------------------------------------------------ timing

/// Runs `f` `reps` times; prints and returns the median nanoseconds per record.
fn timeit(label: &str, records: usize, reps: usize, mut f: impl FnMut() -> u64) -> f64 {
    let mut samples = Vec::with_capacity(reps);
    let mut check = 0u64;
    for _ in 0..reps {
        let start = Instant::now();
        check = black_box(f());
        samples.push(start.elapsed().as_secs_f64() * 1e9 / records as f64);
    }
    samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let (min, median) = (samples[0], samples[reps / 2]);
    println!("  {label:<46} {min:>9.2} {median:>9.2} {:>10.2}   {check:016x}", median * records as f64 / 1e6);
    median
}

fn header(title: &str) {
    println!("\n{title}");
    println!("  {:<46} {:>9} {:>9} {:>10}   {}", "", "min ns", "median ns", "median ms", "checksum");
    println!("  {:<46} {:>9} {:>9} {:>10}", "", "/record", "/record", "/pass");
}

// ------------------------------------------------------------------ part B: native kernel

#[inline(always)]
fn positive(x: f64) -> f64 {
    if x > 0.0 { x } else { 0.0 }
}

/// The toy model's household rules plus `instruments`, written by hand.
/// Returns (income tax, consumption, total of instrument payments).
#[inline(always)]
fn household_native(p: &Params, instruments: &[Instrument], employed: i64, wage: i64, equity: i64, money: i64) -> (i64, i64, i64) {
    let wages = if employed != 0 { wage } else { 0 };
    let market = wages + muldiv(equity, p.pool, p.total_equity);
    let slice1 = (market - p.allowance).max(0).min(p.higher - p.allowance);
    let slice2 = (market - p.higher).max(0);
    let tax = (p.basic_rate * slice1 as f64 + p.higher_rate * slice2 as f64).round_ties_even() as i64;
    let benefits = if employed != 0 { 0 } else { p.benefit };
    let disposable = market + benefits - tax;
    let want = (p.a1 * disposable as f64 + p.a2 * money as f64).round_ties_even() as i64;
    let consumption = want.min(disposable + money);
    let mut extra = 0i64;
    for ins in instruments {
        let over = (market - ins.threshold).max(0);
        let amount = (positive(ins.base - over as f64 * ins.taper).round_ties_even() as i64).min(ins.cap);
        extra += if employed == ins.flag { amount } else { 0 };
    }
    (tax, consumption, extra)
}

fn run_native(p: &Params, instruments: &[Instrument], c: &Columns, out: &mut [Vec<i64>; 3]) {
    for i in 0..c.n {
        let (tax, cons, extra) = household_native(p, instruments, c.employed[i], c.wage[i], c.equity[i], c.money[i]);
        out[0][i] = tax;
        out[1][i] = cons;
        out[2][i] = extra;
    }
}

fn checksum(out: &[Vec<i64>; 3]) -> u64 {
    let mut sum = 0u64;
    for i in 0..out[0].len() {
        sum = sum
            .wrapping_add((out[0][i] as u64).wrapping_mul(3))
            .wrapping_add((out[1][i] as u64).wrapping_mul(5))
            .wrapping_add((out[2][i] as u64).wrapping_mul(7));
    }
    sum
}

// ------------------------------------------------------------------ part B: bytecode

/// Two-address register code. `I` registers hold whole numbers, `F` registers hold reals.
/// The first operand is the destination; a two-register form reads and writes it.
#[derive(Clone, Copy)]
enum Op {
    LoadI(u8, u8),       // I[d] = input column
    StoreI(u8, u8),      // output column = I[a]
    MovI(u8, u8),        // I[d] = I[a]
    MovIC(u8, i64),      // I[d] = c
    AddI(u8, u8),        // I[d] += I[a]
    SubI(u8, u8),        // I[d] -= I[a]
    MinI(u8, u8),        // I[d] = min(I[d], I[a])
    SubIC(u8, i64),      // I[d] -= c
    MaxIC(u8, i64),      // I[d] = max(I[d], c)
    MinIC(u8, i64),      // I[d] = min(I[d], c)
    MaskI(u8, u8),       // I[d] = if I[a] != 0 { I[d] } else { 0 }
    MaskNotI(u8, u8),    // I[d] = if I[a] != 0 { 0 } else { I[d] }
    EqIC(u8, u8, i64),   // I[d] = (I[a] == c) as whole number
    MulDivIC(u8, i64, i64), // I[d] = floor(I[d] * num / den)
    IToF(u8, u8),        // F[d] = I[a] as real
    RoundFToI(u8, u8),   // I[d] = round half to even of F[a]
    MulFC(u8, f64),      // F[d] *= c
    RSubFC(u8, f64),     // F[d] = c - F[d]
    MaxFC(u8, f64),      // F[d] = if F[d] > c { F[d] } else { c }
    AddF(u8, u8),        // F[d] += F[a]
}

const REG_I: usize = 11;
const REG_F: usize = 2;
// Input columns: 0 employed, 1 wage, 2 equity, 3 money. Output columns: 0 tax, 1 consumption, 2 extra.

fn compile(p: &Params, instruments: &[Instrument]) -> Vec<Op> {
    use Op::*;
    let mut code = vec![
        LoadI(0, 0),                     // r0 employed
        LoadI(1, 1),
        MaskI(1, 0),                     // r1 wages
        LoadI(2, 2),
        MulDivIC(2, p.pool, p.total_equity), // r2 dividends
        AddI(1, 2),                      // r1 market income
        MovI(3, 1),
        SubIC(3, p.allowance),
        MaxIC(3, 0),
        MinIC(3, p.higher - p.allowance), // r3 income in the basic band
        MovI(4, 1),
        SubIC(4, p.higher),
        MaxIC(4, 0),                     // r4 income in the higher band
        IToF(0, 3),
        MulFC(0, p.basic_rate),
        IToF(1, 4),
        MulFC(1, p.higher_rate),
        AddF(0, 1),
        RoundFToI(5, 0),                 // r5 income tax
        MovIC(6, p.benefit),
        MaskNotI(6, 0),                  // r6 benefits
        MovI(7, 1),
        AddI(7, 6),
        SubI(7, 5),                      // r7 disposable income
        LoadI(8, 3),                     // r8 money
        IToF(0, 7),
        MulFC(0, p.a1),
        IToF(1, 8),
        MulFC(1, p.a2),
        AddF(0, 1),
        RoundFToI(9, 0),                 // r9 desired spending
        AddI(8, 7),                      // r8 most the household can pay
        MinI(9, 8),                      // r9 consumption
        MovIC(10, 0),                    // r10 instrument payments
    ];
    for ins in instruments {
        code.extend_from_slice(&[
            MovI(3, 1),
            SubIC(3, ins.threshold),
            MaxIC(3, 0),
            IToF(0, 3),
            MulFC(0, ins.taper),
            RSubFC(0, ins.base),
            MaxFC(0, 0.0),
            RoundFToI(4, 0),
            MinIC(4, ins.cap),
            EqIC(6, 0, ins.flag),
            MaskI(4, 6),
            AddI(10, 4),
        ]);
    }
    code.extend_from_slice(&[StoreI(0, 5), StoreI(1, 9), StoreI(2, 10)]);
    code
}

/// Runs each instruction over a whole block of records before moving to the next one.
fn run_batched(code: &[Op], input: [&[i64]; 4], out: &mut [Vec<i64>; 3], n: usize, block: usize) {
    let mut ri = vec![vec![0i64; block]; REG_I];
    let mut rf = vec![vec![0f64; block]; REG_F];
    let mut start = 0;
    while start < n {
        let len = block.min(n - start);
        for op in code {
            match *op {
                Op::LoadI(d, col) => ri[d as usize][..len].copy_from_slice(&input[col as usize][start..start + len]),
                Op::StoreI(col, a) => out[col as usize][start..start + len].copy_from_slice(&ri[a as usize][..len]),
                Op::MovI(d, a) => {
                    let [x, y] = ri.get_disjoint_mut([d as usize, a as usize]).unwrap();
                    x[..len].copy_from_slice(&y[..len]);
                }
                Op::MovIC(d, c) => ri[d as usize][..len].fill(c),
                Op::AddI(d, a) => {
                    let [x, y] = ri.get_disjoint_mut([d as usize, a as usize]).unwrap();
                    for (x, y) in x[..len].iter_mut().zip(&y[..len]) {
                        *x = x.wrapping_add(*y);
                    }
                }
                Op::SubI(d, a) => {
                    let [x, y] = ri.get_disjoint_mut([d as usize, a as usize]).unwrap();
                    for (x, y) in x[..len].iter_mut().zip(&y[..len]) {
                        *x = x.wrapping_sub(*y);
                    }
                }
                Op::MinI(d, a) => {
                    let [x, y] = ri.get_disjoint_mut([d as usize, a as usize]).unwrap();
                    for (x, y) in x[..len].iter_mut().zip(&y[..len]) {
                        *x = (*x).min(*y);
                    }
                }
                Op::SubIC(d, c) => ri[d as usize][..len].iter_mut().for_each(|x| *x = x.wrapping_sub(c)),
                Op::MaxIC(d, c) => ri[d as usize][..len].iter_mut().for_each(|x| *x = (*x).max(c)),
                Op::MinIC(d, c) => ri[d as usize][..len].iter_mut().for_each(|x| *x = (*x).min(c)),
                Op::MaskI(d, a) => {
                    let [x, y] = ri.get_disjoint_mut([d as usize, a as usize]).unwrap();
                    for (x, y) in x[..len].iter_mut().zip(&y[..len]) {
                        *x = if *y != 0 { *x } else { 0 };
                    }
                }
                Op::MaskNotI(d, a) => {
                    let [x, y] = ri.get_disjoint_mut([d as usize, a as usize]).unwrap();
                    for (x, y) in x[..len].iter_mut().zip(&y[..len]) {
                        *x = if *y != 0 { 0 } else { *x };
                    }
                }
                Op::EqIC(d, a, c) => {
                    let [x, y] = ri.get_disjoint_mut([d as usize, a as usize]).unwrap();
                    for (x, y) in x[..len].iter_mut().zip(&y[..len]) {
                        *x = (*y == c) as i64;
                    }
                }
                Op::MulDivIC(d, num, den) => ri[d as usize][..len].iter_mut().for_each(|x| *x = muldiv(*x, num, den)),
                Op::IToF(d, a) => {
                    for (x, y) in rf[d as usize][..len].iter_mut().zip(&ri[a as usize][..len]) {
                        *x = *y as f64;
                    }
                }
                Op::RoundFToI(d, a) => {
                    for (x, y) in ri[d as usize][..len].iter_mut().zip(&rf[a as usize][..len]) {
                        *x = y.round_ties_even() as i64;
                    }
                }
                Op::MulFC(d, c) => rf[d as usize][..len].iter_mut().for_each(|x| *x *= c),
                Op::RSubFC(d, c) => rf[d as usize][..len].iter_mut().for_each(|x| *x = c - *x),
                Op::MaxFC(d, c) => rf[d as usize][..len].iter_mut().for_each(|x| *x = if *x > c { *x } else { c }),
                Op::AddF(d, a) => {
                    let [x, y] = rf.get_disjoint_mut([d as usize, a as usize]).unwrap();
                    for (x, y) in x[..len].iter_mut().zip(&y[..len]) {
                        *x += *y;
                    }
                }
            }
        }
        start += len;
    }
}

/// Runs the whole program for one record before moving to the next record.
fn run_scalar(code: &[Op], input: [&[i64]; 4], out: &mut [Vec<i64>; 3], n: usize) {
    let mut ri = [0i64; REG_I];
    let mut rf = [0f64; REG_F];
    for i in 0..n {
        for op in code {
            match *op {
                Op::LoadI(d, col) => ri[d as usize] = input[col as usize][i],
                Op::StoreI(col, a) => out[col as usize][i] = ri[a as usize],
                Op::MovI(d, a) => ri[d as usize] = ri[a as usize],
                Op::MovIC(d, c) => ri[d as usize] = c,
                Op::AddI(d, a) => ri[d as usize] = ri[d as usize].wrapping_add(ri[a as usize]),
                Op::SubI(d, a) => ri[d as usize] = ri[d as usize].wrapping_sub(ri[a as usize]),
                Op::MinI(d, a) => ri[d as usize] = ri[d as usize].min(ri[a as usize]),
                Op::SubIC(d, c) => ri[d as usize] = ri[d as usize].wrapping_sub(c),
                Op::MaxIC(d, c) => ri[d as usize] = ri[d as usize].max(c),
                Op::MinIC(d, c) => ri[d as usize] = ri[d as usize].min(c),
                Op::MaskI(d, a) => ri[d as usize] = if ri[a as usize] != 0 { ri[d as usize] } else { 0 },
                Op::MaskNotI(d, a) => ri[d as usize] = if ri[a as usize] != 0 { 0 } else { ri[d as usize] },
                Op::EqIC(d, a, c) => ri[d as usize] = (ri[a as usize] == c) as i64,
                Op::MulDivIC(d, num, den) => ri[d as usize] = muldiv(ri[d as usize], num, den),
                Op::IToF(d, a) => rf[d as usize] = ri[a as usize] as f64,
                Op::RoundFToI(d, a) => ri[d as usize] = rf[a as usize].round_ties_even() as i64,
                Op::MulFC(d, c) => rf[d as usize] *= c,
                Op::RSubFC(d, c) => rf[d as usize] = c - rf[d as usize],
                Op::MaxFC(d, c) => rf[d as usize] = if rf[d as usize] > c { rf[d as usize] } else { c },
                Op::AddF(d, a) => rf[d as usize] += rf[a as usize],
            }
        }
    }
}

// ------------------------------------------------------------------ main

fn self_check() {
    assert_eq!(philox4x32_10([0; 4], [0; 2]), [0x6627_E8D5, 0xE169_C58D, 0xBC57_AC4C, 0x9B00_DBD8]);
    assert_eq!(philox4x32_10([u32::MAX; 4], [u32::MAX; 2]), [0x408F_276D, 0x41C8_3B0E, 0xA20B_C7C6, 0x6D54_51FD]);
    assert_eq!(
        philox4x32_10([0x243F_6A88, 0x85A3_08D3, 0x1319_8A2E, 0x0370_7344], [0xA409_3822, 0x299F_31D0]),
        [0xD16C_FE09, 0x94FD_CCEB, 0x5001_E420, 0x2412_6EA1]
    );
    // The value the retired Python reference printed for the same key, and the engine's
    // own rng test checks.
    assert_eq!(uniform(1, 2, 3, 4), 0.282_889_125_902_804_7);
    assert_eq!(muldiv(-7, 10, 3), -24);
    assert_eq!(muldiv(4_611_686_018_427_387_904, 6, 4), 6_917_529_027_641_081_856);
    println!("self-check passed: Philox known answers, uniform() matches the oracle, muldiv floors");
}

fn main() {
    println!("PoliSim S0 micro-benchmarks (single thread)");
    println!(
        "cores available: {}   avx2: {}   avx512f: {}",
        std::thread::available_parallelism().map(|n| n.get()).unwrap_or(0),
        cfg!(target_feature = "avx2"),
        cfg!(target_feature = "avx512f"),
    );
    self_check();
    let reps = 9;

    // ---------------- part A
    let n = 1_000_000;
    let mut c = make_columns(n);
    let total_equity: i64 = (0..n).map(|i| c.weight[i] * c.equity[i]).sum();
    let p = Params {
        allowance: 100_000,
        higher: 400_000,
        basic_rate: 0.20,
        higher_rate: 0.40,
        benefit: 80_000,
        a1: 0.8,
        a2: 0.1,
        pool: 172_000_000_000,
        total_equity,
    };
    let mut out = [vec![0i64; n], vec![0i64; n], vec![0i64; n]];
    header(&format!("A. Passes over {n} person records held as columns"));
    let mut total = 0.0;

    total += timeit("ageing (one small-integer column)", n, reps, || {
        c.age_months.iter_mut().for_each(|a| *a = a.saturating_add(1));
        c.age_months.iter().map(|a| *a as u64).sum()
    });

    const HAZARD: [f64; 10] = [0.0004, 0.0001, 0.0001, 0.0002, 0.0003, 0.0006, 0.0015, 0.004, 0.011, 0.03];
    let mut step = 0u32;
    total += timeit("mortality draw (1 random number each)", n, reps, || {
        step += 1;
        let mut deaths = 0u64;
        for i in 0..n {
            let band = ((c.age_months[i] / 120) as usize).min(9);
            if uniform(1, 1, i as u64, step) < HAZARD[band] {
                deaths += c.weight[i] as u64;
            }
        }
        deaths
    });

    total += timeit("job transition (2 random numbers each)", n, reps, || {
        step += 1;
        let (leave, hire) = (0.02, 0.30);
        let mut employed = 0u64;
        for i in 0..n {
            let stays = !(uniform(1, 2, i as u64, step) < leave);
            let hired = uniform(1, 3, i as u64, step) < hire;
            c.employed[i] = (if c.employed[i] != 0 { stays } else { hired }) as i64;
            employed += c.employed[i] as u64;
        }
        employed
    });

    total += timeit("toy tax, benefit and spending rules", n, reps, || {
        run_native(&p, &[], &c, &mut out);
        checksum(&out)
    });

    total += timeit("weighted totals by region (128-bit sums)", n, reps, || {
        let mut sums = [[0i128; 3]; 12];
        for i in 0..n {
            let (r, w) = (c.region[i] as usize, c.weight[i] as i128);
            sums[r][0] += w * out[0][i] as i128;
            sums[r][1] += w * out[1][i] as i128;
            sums[r][2] += w;
        }
        sums.iter().fold(0u64, |acc, s| acc.wrapping_add(s[0] as u64).wrapping_add(s[1] as u64).wrapping_add(s[2] as u64))
    });

    total += timeit("opinion drift (4 real columns)", n, reps, || {
        const TARGET: [f64; 12] = [-0.5, -0.3, -0.2, -0.1, 0.0, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6];
        let mut acc = 0.0f64;
        for axis in 0..4 {
            let column = &mut c.opinion[axis];
            for i in 0..n {
                column[i] += 0.02 * (TARGET[c.region[i] as usize] - column[i]);
            }
            acc += column[n / 2];
        }
        acc.to_bits()
    });
    println!("  {:<46} {:>9} {total:>9.2} {:>10.2}", "all six passes", "", total * n as f64 / 1e6);

    // ---------------- part B
    let h = 100_000;
    let hc = make_columns(h);
    let h_equity: i64 = (0..h).map(|i| hc.weight[i] * hc.equity[i]).sum();
    let hp = Params { total_equity: h_equity, pool: 17_200_000_000, ..p };
    let input: [&[i64]; 4] = [&hc.employed, &hc.wage, &hc.equity, &hc.money];
    let mut results = Vec::new();
    for k in [0usize, 20, 200] {
        let instruments = make_instruments(k);
        let code = compile(&hp, &instruments);
        let ops = code.len();
        header(&format!("B. Household rules, {h} households, {k} extra instruments ({ops} operations each)"));
        let mut o1 = [vec![0i64; h], vec![0i64; h], vec![0i64; h]];
        let native = timeit("hand-written Rust", h, reps, || {
            run_native(&hp, &instruments, &hc, &mut o1);
            checksum(&o1)
        });
        let want = checksum(&o1);
        let mut o2 = [vec![0i64; h], vec![0i64; h], vec![0i64; h]];
        let batched = timeit("bytecode, 1024 records per block", h, reps, || {
            run_batched(&code, input, &mut o2, h, 1024);
            checksum(&o2)
        });
        assert_eq!(checksum(&o2), want, "batched bytecode disagrees with native");
        if k == 20 {
            for block in [64usize, 256, 4096, 16384] {
                timeit(&format!("bytecode, {block} records per block"), h, reps, || {
                    run_batched(&code, input, &mut o2, h, block);
                    checksum(&o2)
                });
                assert_eq!(checksum(&o2), want);
            }
        }
        let mut o3 = [vec![0i64; h], vec![0i64; h], vec![0i64; h]];
        let scalar = timeit("bytecode, one record at a time", h, reps, || {
            run_scalar(&code, input, &mut o3, h);
            checksum(&o3)
        });
        assert_eq!(checksum(&o3), want, "scalar bytecode disagrees with native");
        results.push((k, ops, native, batched, scalar));
    }

    println!("\nSummary: nanoseconds per household, and milliseconds per monthly step at 100,000 households");
    println!("  {:>11} {:>10} | {:>8} {:>8} {:>8} | {:>8} {:>8} {:>8} | {:>14}", "instruments", "operations", "native", "batched", "scalar", "native", "batched", "scalar", "ns/op batched");
    for (k, ops, native, batched, scalar) in results {
        println!(
            "  {k:>11} {ops:>10} | {native:>8.1} {batched:>8.1} {scalar:>8.1} | {:>8.2} {:>8.2} {:>8.2} | {:>14.3}",
            native / 10.0, batched / 10.0, scalar / 10.0, batched / ops as f64
        );
    }
}
