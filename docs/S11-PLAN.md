# Stage S11: effect curves, who loses out, and a faster engine

Written 2026-11-14, after S10, at the owner's request: "Add A and D, release far from
ready yet. Optimise the engine too while at it". A is poverty and median income in the UK
model and the client, checked against the government's statistics; D is effect curves,
with the UK's behaviour moved onto them. Release work waits.

## Decisions

| Question | Decision | Why |
|---|---|---|
| What an effect curve is | A second kind of `[table]`: `kind = "curve"`, an input unit, an output unit and at least two points, straight lines between them and level beyond the ends; `curve(x, table)` reads it. A point's coordinates are national formulas, so a curve can be written from parameters and keeps their presets | Any S-shaped, saturating or lopsided response can be drawn with a few points; the arithmetic is fixed, so oracle and engine give the same bits; tables already carry formula-valued points (marginal-rate bands) |
| Mods | A mod may add tables, so it can bring its own curves | Curves are how a mod would shape its effects |
| People, not households | `quantile` takes an optional count per record: each record counts that many times its weight | Poverty statistics count people; a median person's income needs households weighted by their members |
| Which UK responses become curves | Inflation's response to the unemployment gap (steeper when the labour market is tight, flatter when it is slack); NHS treatments' response to real health spending (cuts bite harder than rises help, and rises run into diminishing returns); voters' response to how services and the climate measure have moved since the last election (a fall counts more than a rise) | Each was a straight line through the 2024 point. Each curve goes through that point with the same slope there, so the base month still reproduces 2024; they differ only away from it. They are documented judgements with presets, as the straight lines were |
| What the UK's voting fit becomes | Unchanged | S9.4 fitted the reactions to income and unemployment, which stay straight lines |
| How poverty is measured | As the government's Households Below Average Income (HBAI) does, before housing costs: each household's net income divided by the modified OECD scale (0.67 for the first adult, 0.33 for each other adult and each child of 14 or over, 0.2 for each younger child), the median person's equivalised income, and the share of people (children, working-age adults, pensioners) in households below 60% of it | The headline UK measure; DWP publishes it under the Open Government Licence |
| What the households can and cannot match | Our households carry children under 16 and 16 or 17, not 14, so 14- and 15-year-olds take a younger child's 0.2; net income lacks council tax, housing benefit and disability benefits, and the households are built from ONS tables, not the survey HBAI uses. So the measures are compared with HBAI 2023/24 and the differences reported, not fitted away | Honest about a synthetic population |

## Milestones

| # | Milestone | Done when |
|---|---|---|
| S11.1 | Effect curves | `kind = "curve"` tables and `curve()` in oracle, engine, specs 01 and 02, and shared cases; mods may add tables; the random models use curves |
| S11.2 | Counted quantiles | `quantile(entity, x, p, n)` in oracle, engine, spec and shared cases |
| S11.3 | The UK on curves | The three curves in the UK model, the base month unchanged, the recorded hashes and checks regenerated, the effects reported |
| S11.4 | Who loses out | Equivalised income, the median and relative poverty (all, children, working-age adults, pensioners) in the UK model and the client, compared with HBAI 2023/24 |
| S11.5 | A faster engine | Profiles of the UK's month after S11.3 and S11.4, and the measured wins taken; every hash the same |

## Status

| # | Status |
|---|---|
| S11.1 | Done. `[table.x]` with `kind = "curve"`, `x_unit`, `unit` and `points` (spec 01) and `curve(x, table)` (spec 02): the points' x must ascend, checked at each use; level beyond the ends; `y_k + (y_k+1 - y_k) * ((x - x_k) / (x_k+1 - x_k))` between. The conformance model gains three curves (one whose points stop ascending once a parameter is read), and 188 shared cases follow the earlier ones in `conformance/cases.tsv`: every point, both ends, infinities, not-a-number, -0.0, whole numbers, money, per record, nested, and every refusal. Mods may add tables. The random models use curves (60 times among the 80) and the engine matches them on one, two and eight threads |
| S11.2 | Done. `quantile(entity, x, p, n)`: `n` for every record after `x`, then `p`; a count below zero is an error; each record counts its weight times `n`, exactly. 92 shared cases (4,577 in all; every earlier case unchanged) |
| S11.4 | Done. `households.toml` (from `tools/uk/make_rules.py`) gains each household's people, pensioners, equivalence scale and equivalised net income; the median person's equivalised income (`quantile` counted by people); the poverty line at 60% of it; and the shares of everyone, children, working-age adults and pensioners in households below it, also as `poverty_by_group`, which the client's "Who gains, who loses" panel lists. In January 2025 the median is £657 a week (HBAI 2023/24: £650); in poverty: everyone 19.6% (17%), children 21.0% (23%), working-age adults 16.7% (15%), pensioners 27.7% (19%). The pensioners' gap is the one expected: the households have no Pension Credit, housing or disability benefits. Nothing the model computed before changes: every recorded hash is the same. Source: DWP, Households Below Average Income 2023/24, summary tables 1.2b to 1.6a (OGL v3) |
