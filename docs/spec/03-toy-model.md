# The toy model and its target patterns

`models/toy/` is the smallest model that still behaves like an economy. It exists to
exercise every feature of format 0 and to give the engine something exact to reproduce.
It describes no real country and its numbers are invented.

Related: [engine contract](00-engine-contract.md), [model format](01-model-format-v0.md),
[formula language](02-formula-language-v0.md).

## Structure

Three sectors and one financial asset. The government issues **money**; households and
firms hold it. There are no banks, no bonds, no interest, no prices and no foreign sector.

- **Households**: 1,000 records standing for 1,004,721 households. Each record has a
  weight, a wage it earns when employed, a number of shares in the firm sector, an
  employment status and a money balance.
- **Firms**: one account. They hire to match demand, pay wages, collect sales, hand VAT
  to the government and pay out half their money to shareholders each month.
- **Government**: buys from firms, pays a benefit to households without work, and
  collects income tax (an allowance, a basic rate, a higher rate) and VAT.

Six policy levers: government purchases, the benefit, the personal allowance, the basic
and higher income-tax rates, and the VAT rate.

## Transactions

Every monthly flow, with the payer negative and the receiver positive. Each row sums to
zero, and each column's sum is that sector's change in money.

| Flow | Households | Firms | Government |
|---|:---:|:---:|:---:|
| wages | + | − | |
| dividends | + | − | |
| benefits | + | | − |
| income tax | − | | + |
| consumption | − | + | |
| VAT | | − | + |
| government purchases | | + | − |
| **change in money held** | ΔM households | ΔM firms | −Δ(money issued) |

## Behaviour

The equations are in `models/toy/economy.toml`; in words, by phase:

1. **Labour.** Firms want a wage bill of 60% of last month's sales net of VAT and close
   half the gap each month. Every employed household has a 2% chance of losing its job
   regardless; beyond that, households are laid off or hired at random so that the
   expected wage bill hits the target.
2. **Income.** Employed households are paid their wage. Firms pay out half the money they
   hold, split by shares and rounded down per household. Households without work get the
   benefit. Income tax is charged on wages plus dividends.
3. **Spending.** A household spends 80% of the month's disposable income plus 10% of the
   money it held at the start of the month, never more than it has.
4. **Firms.** VAT is the tax-inclusive share of consumption. Net sales are consumption
   minus VAT plus government purchases; they drive next month's hiring.
5. **Government.** Totals, the budget balance and the unemployment rate.

Demand drives output and nothing limits supply except the number of households, so the
model is only meaningful below full employment. A supply side is out of scope here and
belongs to the first real country model.

## Target patterns

These are the behaviours the model was required to show before it was accepted. Each is
a test in `tests/test_patterns.py`; "measured" is what the model produced with
the central preset and seed 20261113. Policy changes are made at step 120 and compared
with the unchanged baseline run on the same seed. Because random draws depend only on
seed, stream, household and step, the two runs share every draw, which is what allows
the exact equalities below.

| # | Pattern | Required | Measured |
|---|---|---|---|
| 1 | Every sector's money changes by exactly its net flows, and all balances sum to zero | exact, every step | holds for 360 steps |
| 2 | The reported budget balance equals the change in money issued | exact, every step | holds |
| 3 | Household records add up to the household account; no balance goes negative | exact, every step | holds |
| 4 | With policy unchanged the economy settles with a balanced budget | mean balance under 0.1% of GDP; unemployment 4% to 8% | 0.0002% of GDP; 6.1% |
| 5 | Other seeds settle in the same place | GDP within 0.5%, unemployment within 1.5 points | within 0.03%; within 0.2 points |
| 6 | Extra government purchases raise output by exactly that amount in the first month | exact | £100m gives £100m |
| 7 | The long-run spending multiplier is about two, and the budget returns to balance | 1.8 to 2.2; balance change under 5% of the extra spending | 2.00; 0.1% |
| 8 | A spending cut improves the budget by the full cut only in the first month | exact in month one; 20% to 60% over the next three months | exact; 39% |
| 9 | Automatic stabilisers then undo the saving: benefits and unemployment rise | long-run improvement under 5% of the cut | 0.1%; unemployment up 6.0 points |
| 10 | A higher basic rate shrinks output and employment | GDP down more than 2%; unemployment up more than 1 point | down 3.3%; up 2.9 points |
| 11 | A higher top rate costs only households above the threshold, in the month it changes | nobody gains; households at or below the threshold are unchanged, to the penny | holds; the top tenth's share of income falls |
| 12 | Saving more cuts output at first but not in the long run, and money held rises to 3 months of income from 2 | early GDP down more than 3%; long-run GDP within 0.5%; money ratio 1.5 within 1% | down 6.6%; within 0.01%; 1.500 |
| 13 | The baseline reproduces its recorded state hash on every step | all 240 hashes | holds |

Patterns 4, 7, 9 and 12 are the textbook properties of a stock-flow consistent model with
government money: a stationary state needs a balanced budget, so long-run output is set
by government spending and the tax system, not by how much households like to save.
Their appearance here, from household-level rules and to the stated precision, is the
evidence that the accounting and the aggregation are right.

## Recorded run

`models/toy/golden/baseline.hashes.csv` holds the state hash of each of the baseline's
240 steps. Regenerate it only when the model or the contract changes on purpose:

```bash
cargo build --release
target/release/polisim run models/toy/scenarios/baseline.toml --columns step,hash --out models/toy/golden/baseline.hashes.csv
```

`python tools/record_goldens.py` re-records every model's hashes this way, and
`python tools/record_goldens.py --check` checks them without writing.
