# Stage S4: households

Written 2026-11-14, after S3. The roadmap's line for this stage: a synthetic population of
20,000 then 100,000 households; real tax and benefit rules; alignment to the cohort table.
It is the stage where policy gets winners and losers.

## Decisions

Proposed here, and taken as decided unless the owner changes them.

| Question | Decision | Why |
|---|---|---|
| Where households come from | Synthetic, built only from published tables: the mid-2024 population (already in the pipeline), Census 2021 household composition by region, ASHE 2024 earnings percentiles, DWP caseloads and HMRC income tax statistics | The roadmap says synthetic. Survey microdata (FRS, LCF) need a UK Data Service licence that forbids redistribution and commercial use, so they cannot ship in the game. Published tables are OGL v3 |
| How they are built | Draw records from published distributions, then weight them by raking (iterative proportional fitting) so that the weighted households match the published totals: people by region, sex and age group; households by type and region; earnings by decile; income tax payers by band | The standard method for synthetic populations; every target is a published number, so every check is too |
| Size | 20,000 households first, 100,000 once the rules are complete | The engine stepped 100,000 households in 12 ms on toy rules; rule depth is the open cost (S0 put it at 55 to 71 ms for a deep system) |
| Tax year | 2024-25, matching the base year | The national model is calibrated to 2024 |
| Rules | Income tax (rest of UK and Scottish bands), National Insurance (employee, employer, self-employed), child benefit with the high-income charge, the state pension, Universal Credit (standard allowance, child and housing elements, work allowance, 55% taper), council tax by band | The rules that decide most households' net income. Rates and thresholds come from GOV.UK, OGL v3. Disability benefits, tax credits' remains and the benefit cap come later |
| What the player gets | The tax levers become the real ones (allowance, rates, thresholds, UC taper); a "who gains, who loses" view by income decile, household type and region | The point of the stage |
| Alignment to the cohort table | Weights adjusted once a year by raking to the cohort table's people by region, sex and age group | Keeps the households consistent with the population as it ages, without simulating births and deaths household by household |

## Engine work this needs

Two features format 1 left out (`docs/spec/06-model-format-1.md`, "Not in format 1"):

- **aggregates of records by a dimension**: income tax paid by households in each region,
  people by age group. A `wsum` whose result has a dimension, keyed by a record's column.
- **weights that change**: entity weights are fixed data today. Alignment needs them as
  state, updated by a native raking operator with an exact order of evaluation.

Both go through the usual path: specification, oracle, engine, conformance cases.

## Milestones

| # | Milestone | Done when |
|---|---|---|
| S4.0 | Format 1.1: aggregates by dimension | Oracle and engine agree on a test model that uses them; conformance cases recorded |
| S4.1 | Synthetic households, 20,000 | `tools/uk/households.py` builds them from cached published tables; the weighted records match every target within 1% and the report lists each target and its error |
| S4.2 | Tax and benefit rules, 2024-25 | Income tax and National Insurance on the households within 5% of HMRC's receipts for 2024-25; child benefit and state pension caseloads and spending within 5% of DWP's |
| S4.3 | Households feed the national model | The national model's household income, taxes and benefits come from the households; the 2024 base month still reproduces the national accounts |
| S4.4 | Weights that change, 100,000 households | Format 1.2 raking operator; after ten years the weighted households match the cohort table by region, sex and age group; a month of 100,000 households takes under 100 ms |
| S4.5 | Who gains, who loses | The client shows the effect of any policy change by income decile, household type and region, from the households, with the national totals adding up |

## What could go wrong

| Risk | Sign | Response |
|---|---|---|
| Raking does not converge when targets conflict | Errors that do not shrink between passes | Report the conflict; loosen the least reliable target first (recorded in the report) |
| Synthetic households miss the joint distribution (earnings by household type) | Tax by household type far from HMRC's tables | Add the joint table as a target before adding rules |
| Universal Credit's detail grows without end | S4.2 slips | The rule list above is the scope; the rest goes to the list for S6 |
| Rule depth makes 100,000 households slow | S4.4 timing fails | Profile per rule; the engine's block evaluation already amortises dispatch |

## Status

| # | Status |
|---|---|
| S4.0 | Done. `wsum_by` and `wcount_by` total records by a dimension (`docs/spec/06-model-format-1.md`); oracle and engine agree on `models/cohort` and 13 new conformance cases |
| S4.1 | Done. `tools/uk/households.py` builds 20,000 households from ONS tables only (households by type, ASHE pay by region, sex and age, the mid-2024 population) and weights them by exponential calibration: 28.6 million households and 67.4 million people in them, with every one of 179 targets (households by type; people by region, sex and age band; people in work) within 0.03%. Weighted earnings come to £1,220bn and pensions to £173bn. Assumptions (employment by age, self-employment, pensions, people outside households) are listed in `models/uk/households/HOUSEHOLDS.md` |
| S4.2 | Built, one check missed. `models/uk/households/` runs 2024-25 income tax (rest of the UK and Scotland), National Insurance, Child Benefit with the high-income charge and Universal Credit on the 20,000 households, every rate a lever (GOV.UK values, checked 2026-11-14). National Insurance comes to £176bn against £173bn published (within 2%); income tax to £247bn against £310bn, the gap being tax on savings, dividends, property and capital gains, which the records do not have yet. Oracle and engine agree byte for byte. Details: `models/uk/households/README.md` |
| S4.3 | Next: households feed the national model |
