# UK households, 2024-25 rules

A model of the UK's 28.6 million households as 20,000 weighted records (stage S4 of
`docs/PLAN.md`; plan in `docs/S4-PLAN.md`), with 2024-25 tax and benefit rules.

| File | What it holds | Made by |
|---|---|---|
| `households.csv`, `HOUSEHOLDS.md` | The records and their calibration report (every target and its error, every assumption) | `python tools/uk/households.py` |
| `model.toml`, `rules.toml` | The model: the records as the entity `household`, and the rules | `python tools/uk/make_rules.py` |
| `scenarios/base.toml`, `golden/` | A three-month run and the oracle's state hashes, which the engine reproduces | by hand; the oracle |

## The records

Built from ONS tables only (no survey microdata): households by type (Families and
households, 2024), employees' pay by region, sex and age group (ASHE 2024 percentiles), and
the mid-2024 population. Each record has a region, a household type, up to four adults
(age, sex, pay or self-employment profit, pension) and its children. Weights come from
exponential calibration to 179 published totals, all met within 0.03%.

Pay above the 99th percentile follows a Pareto tail (index 2, the 99th percentile at twice
the 90th), chosen so that National Insurance, the one check that depends on pay alone,
comes within 2% of the published total.

## The rules

Every rate and threshold is a lever, at its 2024-25 value from GOV.UK. Per adult: income
tax (rest of the UK or Scotland, by region) on pay, profit and pensions after a personal
allowance withdrawn above £100,000; employee and employer National Insurance; Class 4 on
profit. Per household: Child Benefit less the High Income Child Benefit Charge; Universal
Credit for working-age benefit units (standard allowance, child elements with the two-child
limit, work allowance, 55% taper, pensions deducted in full).

## Who gains, who loses

Each record carries `income_decile`: its tenth of households by equivalised gross income in
the base year (pay and pensions over the modified OECD scale: 1 for the first adult, 0.5
for each other adult, 0.3 for each child), poorest first, each tenth holding a tenth of the
weighted households. The rules give each household's net income a month (pay and pensions
after income tax and National Insurance, with Child Benefit net of the charge and Universal
Credit) and average it by decile, household type and region (`net_income_by_decile`,
`net_income_by_household_type`, `net_income_by_region`) and over all households
(`net_income_average`). The groups' averages, weighted by their households, add up to the
national average (tested in `oracle/tests/test_households.py`). In the first month net
income runs from about £10,200 a year in the poorest tenth to £105,000 in the richest; all
households average £41,800.

Deciles are fixed in the base year: a household keeps its decile when its income changes,
so the panel compares the same households before and after a policy. The client shows the
three breakdowns in its "Who gains, who loses" panel (`docs/spec/05-game-client.md`).

## First month against published totals (a year)

| | Households | Published | Note |
|---|---:|---:|---|
| National Insurance | £176.2bn | £173.3bn (2024) | within 2% |
| Income tax | £246.7bn | £310.1bn (2024) | the published total also taxes savings, dividends, property income and capital gains, which the records do not have yet |
| Child Benefit, net of the charge | £14.2bn | | |
| Universal Credit | £29.8bn | | no housing, disability or carer elements, and everyone entitled claims |
| Pay | £1,279bn | | |
| Pensions | £173bn | | |

## Simplifications

Weekly National Insurance thresholds are applied to annual pay (52 weeks). The benefit unit
is the first two adults of a couple household, or the first adult otherwise. A first child
counts as born before April 2017 when the youngest child is seven or older. There are no
rents, so no housing element; no savings or investment income; no disability benefits;
everyone entitled to Universal Credit claims it. In the national model
(`models/uk/households.toml`) the records' pay follows the economy's pay level and the
thresholds rise with prices; their employment and weights do not change yet (S4.4).
