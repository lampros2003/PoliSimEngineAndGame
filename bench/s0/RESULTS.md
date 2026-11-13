# S0 micro-benchmark results

Recorded 2026-11-13 with `rustc 1.97.0`, release build, one thread, on a shared cloud
machine (Intel Xeon at 2.1 GHz, 4 cores). Each figure is the median of 9 runs. A shared
machine is noisy and slower per core than a current laptop, so read these as orders of
magnitude. They have not been run on the target hardware yet.

Reproduce with:

```bash
cargo run --release --manifest-path bench/s0/Cargo.toml
```

```bash
RUSTFLAGS="-C target-cpu=x86-64-v3" cargo run --release --manifest-path bench/s0/Cargo.toml
```

## What was measured

**Part A** runs six passes of the kind a monthly step makes over 1,000,000 person
records stored as plain columns.

**Part B** runs one household rule set over 100,000 households three ways:

- hand-written Rust, one household at a time;
- bytecode executed a block of records at a time (each instruction loops over the block);
- the same bytecode executed one household at a time.

The rule set is the toy model's tax, benefit and spending rules (37 operations) plus
0, 20 or 200 synthetic means-tested instruments of 12 operations each. 2,437 operations
per household is meant to stand in for a full statutory tax and benefit system.

## Median nanoseconds per record

| | x86-64 (SSE2) | x86-64-v2 (SSE4.2) | x86-64-v3 (AVX2) | native (AVX-512) |
|---|---:|---:|---:|---:|
| **A. 1,000,000 persons** | | | | |
| ageing (one small-integer column) | 0.25 | 0.19 | 0.14 | 0.14 |
| mortality draw (1 random number each) | 11.61 | 11.74 | 12.01 | 11.83 |
| job transition (2 random numbers each) | 20.41 | 14.98 | 8.91 | 7.18 |
| toy tax, benefit and spending rules | 19.82 | 20.46 | 13.12 | 13.65 |
| weighted totals by region (128-bit sums) | 2.98 | 2.95 | 2.91 | 3.11 |
| opinion drift (4 real columns) | 3.50 | 3.60 | 3.40 | 4.00 |
| **all six passes** | **58.57** | **53.92** | **40.49** | **39.91** |
| **B. 37 operations per household** | | | | |
| hand-written Rust | 18.90 | 19.68 | 11.91 | 11.87 |
| bytecode, 1,024 records per block | 23.81 | 15.02 | 14.29 | 13.50 |
| bytecode, one record at a time | 67.52 | 73.16 | 62.14 | 64.47 |
| **B. 277 operations per household** | | | | |
| hand-written Rust | 109.63 | 80.29 | 76.75 | 85.16 |
| bytecode, 64 records per block | 201.71 | 81.54 | 67.48 | 61.05 |
| bytecode, 256 records per block | 197.99 | 77.28 | 64.56 | 65.53 |
| bytecode, 1,024 records per block | 219.22 | 88.22 | 67.50 | 65.01 |
| bytecode, 4,096 records per block | 235.35 | 87.11 | 77.48 | 74.39 |
| bytecode, 16,384 records per block | 250.84 | 96.51 | 101.06 | 113.46 |
| bytecode, one record at a time | 528.10 | 549.59 | 443.56 | 512.31 |
| **B. 2,437 operations per household** | | | | |
| hand-written Rust | 763.17 | 542.19 | 629.91 | 730.38 |
| bytecode, 1,024 records per block | 1,668.74 | 708.02 | 560.66 | 547.86 |
| bytecode, one record at a time | 5,581.56 | 5,366.02 | 4,662.48 | 4,694.05 |

To turn a row into time per monthly step, multiply by the number of records: 100
nanoseconds per record is 10 milliseconds at 100,000 records.

## What the numbers say

1. **Block-wise bytecode is enough; no just-in-time compiler is needed.** From SSE4.2
   upward it runs within about 30% of hand-written Rust, and at AVX2 it is faster than
   the hand-written version at depth, because each instruction becomes a tight loop the
   compiler vectorises. It costs 0.23 to 0.41 nanoseconds per operation per household.
2. **One record at a time is not enough.** The same bytecode run per household is 3 to 9
   times slower than the block-wise form and would take about half a second per step for
   a deep rule set at 100,000 households.
3. **A deep rule set fits the budget.** At 2,437 operations per household the block-wise
   interpreter takes 0.55 to 0.71 microseconds per household from SSE4.2 upward: 55 to
   71 milliseconds per step at 100,000 households on one thread. The one published
   figure the research report found for a full system, about 100 microseconds per
   household, is roughly 150 times slower than this; that system does things this
   synthetic one does not, so the comparison is loose.
4. **The plain x86-64 build is the outlier.** Without SSE4.1 there is no single
   instruction for rounding a real or for 64-bit minimum and maximum, and the block-wise
   interpreter drops to 1.7 microseconds per household. Requiring x86-64-v2 (processors
   from about 2009) removes that; x86-64-v3 (AVX2, from about 2013) gains a further 20%.
5. **Blocks of 64 to 1,024 records are all fine.** Larger blocks fall out of the fast
   cache and slow down.
6. **Population passes cost 40 to 60 nanoseconds per person for all six**, or 40 to 60
   milliseconds per step for a million people on one thread. A random draw costs about
   10 nanoseconds and dominates; the arithmetic passes are close to free.
7. **Results do not depend on the instruction set.** All 19 checksums are identical
   across the four builds, and `uniform()` returns the same bits as the Python oracle.

## What this does not show

- Integer arithmetic wraps here. The engine must detect overflow; that cost is not measured.
- The instruments are synthetic and all have one shape. Real rules include lookups
  across household members, which this does not exercise.
- Nothing here is multi-threaded, and nothing was run on a laptop.
- Inputs are copied into registers and results copied out; a real plan could avoid some copies.
