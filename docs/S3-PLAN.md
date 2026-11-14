# Stage S3: the United Kingdom's national books

Written 2026-11-14. The roadmap's exit test for this stage: the base year reproduces the
published accounts by construction, and a 10 to 20 year hindcast stays inside stated
bands on headline aggregates. Households, regions' people, parties and elections are
later stages; this stage is the national economy and the government's accounts.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Base year | 2024 (calendar year) | The latest year with settled sector accounts in the 2026 releases; 2025 is in the data but will be revised more |
| Step | One month, as for every model | Flows are calibrated as one twelfth of the base year's annual totals |
| Sectors | Households (with non-profit institutions), non-financial corporations, financial corporations, general government, rest of the world | The UK sector accounts' own split (ESA 2010: S.1M, S.11, S.12, S.13, S.2); the central bank sits inside financial corporations until monetary policy needs it on its own |
| First version's format | Model format 0, national values only | A five-sector stock-flow model needs no dimensions, so the engine does not have to change before the economics is checked |
| Industries, cohorts, regions | Model format 1, second half of the stage | They need dimensions (industry, age, sex, region) and native operators (cohort ageing); format 1 is designed once the national model works |
| Data | ONS datasets by series code, pulled by one command | All ONS time-series datasets are under the Open Government Licence v3.0 (checked on the publisher's pages, `docs/data/first-country-licences.md`) |
| What is committed | Extracted series and derived parameters, with a provenance manifest and the attribution statement | The licence allows redistribution with attribution; committing the extracts makes every run reproducible without the network |

## Milestones

| # | Milestone | Built | Done when |
|---|---|---|---|
| S3.0 | Data pipeline | `tools/uk/`: download ONS datasets (UK Economic Accounts, Quarterly National Accounts, Public Sector Finances, Labour Market Statistics) into a local cache; a catalogue of every series used, by code, with its meaning; extraction to `models/uk/data/` with a manifest of source, release date and checksum | One command rebuilds every committed data file byte for byte from the cached downloads |
| S3.1 | Base-year sector accounts | A transaction-flow matrix for 2024: every sector's resources and uses for each transaction the model uses, from the published accounts | Each transaction sums to zero across sectors, and each sector's net lending matches the published figure, within the published statistical discrepancy, which is shown, not hidden |
| S3.2 | UK national model v0 | `models/uk/`: the five sectors, monthly, with consumption, investment, imports, exports, wages and employment, taxes by type, government spending by broad function, benefits and debt interest; parameters derived so that the first months reproduce 2024 | The first twelve steps sum to the 2024 accounts within rounding; the model runs 30 years without leaving its declared ranges; the oracle and the engine agree on it |
| S3.3 | Playable UK | A UK scenario for the client: real budget lines, the real tax rates and spending categories as levers, 2025 start | The client opens it with no change to its code; the budget screen matches the published 2024 public finances |
| S3.4 | Hindcast harness | Run the model from 2005 with the actual paths of exogenous inputs (world demand, policy settings, Bank Rate) and compare GDP, unemployment, borrowing and debt with outturns | Stated bands met, or the misses explained and recorded |
| S3.5 | Format 1 | Dimensions, indexed parameters from tables, sums over dimensions, cohort ageing as a native operator; oracle first, then engine, then conformance cases | Engine and oracle agree on a test model using every new feature |
| S3.6 | Industries and people | 10 to 15 industries from the ONS input-output analytical tables; a population cohort table by single year of age, sex and the 12 ITL1 regions from ONS estimates and projections | Industry outputs sum to national output; the cohort table reproduces ONS's published population for the base year |

S3.0 to S3.3 come first: they give a playable United Kingdom without any engine change.
S3.5 and S3.6 then add the detail S4 (households) builds on.

## Status

| # | Status |
|---|---|
| S3.0 | Done. `python tools/uk/pipeline.py` rebuilds `models/uk/data/` from the cached downloads |
| S3.1 | Done in a narrower form than planned: `models/uk/data/CHECKS.md` shows the three identities (GDP by expenditure, sector balances, the public sector's borrowing) close for every year from 2000 to 2024: exactly, except sector balances, which are off by at most £5 million (rounding in the published figures); 2025 is incomplete and does not close, and the model's first month reproduces the 2024 net lending of households and financial corporations. A full transaction-by-sector matrix was not needed for a five-sector model and is left for S3.6 |
| S3.2 | Built. `models/uk/`, calibrated by `tools/uk/calibrate.py`; tests in `oracle/tests/test_uk.py` and `crates/core/tests/golden.rs`; random scenarios compared with `python tools/diff_engine.py --model models/uk`. Known weaknesses are listed in `models/uk/README.md` |
| S3.3 | Next |

## Bands for the hindcast (S3.4)

To be confirmed when the harness exists; proposed now so the target is not chosen after
seeing the results:

| Figure | Band |
|---|---|
| Nominal GDP, annual | Within 5% of outturn in every year |
| Public sector net borrowing, annual | Within 2 percentage points of GDP |
| Unemployment rate, annual average | Within 1.5 percentage points |
| Public sector net debt, end of year | Within 10 percentage points of GDP after 10 years |

These are wide on purpose: the first version has no supply side beyond labour, no
financial crisis mechanism and no inflation model of its own, so 2008 and 2020 will be
missed unless they enter as shocks to exogenous inputs, which is how the harness treats
them.

## What could go wrong

| Risk | Sign | Response |
|---|---|---|
| The accounts do not close tightly enough to calibrate by construction | Sector net lending off by more than the discrepancy | Assign the statistical discrepancy to the rest of the world, as the ONS presentation does, and record it |
| Series codes change between ONS releases | The pipeline fails to find a code | The catalogue names every code; the pipeline stops with the missing code rather than guessing |
| A model with monthly steps calibrated to annual totals oscillates | Hindcast shows cycles that are not in the data | Calibrate adjustment speeds per month explicitly (the roadmap's note on quarterly versus monthly) |
| Scope grows towards a full macro model | Milestones slip | The milestone table is the scope; anything else goes to a list for S6 |
