# PoliSim S13: balance report, the UK 2025 term

Played on 2026-11-15 against the model as it stands (no model file changed). Stage S13.7 changed the
model on these findings and played the strategies again: "After S13.7", below; stage S13.8
made the public finances matter and played them a third time: "After S13.8".

## Method

- Every strategy was played over the 60 months of `models/uk/scenarios/2025.toml` through `polisim play`
  (`target/release/polisim.exe`), driven by a scratch Python script: the same `Simulation` as the game, with the
  Commons votes and political capital, the same seed (so the chance questions come in the same months), each
  question answered as it was asked. Values were read after every month. The election result by bloc was read by
  replaying each strategy's exact commands through the Godot bridge (`PoliSim.cells("seats")`); the replays matched
  the command-line runs to four decimals of the final poll rating.
- "Approval" is `government_support` (the governing blocs' share of voting intention), as the centre of the board
  shows it. Balance is the public sector balance at an annual rate.
- The policies were measured one at a time: each of the nineteen set to each end of its range in July 2025
  (when every bill is affordable), then left, against doing nothing; the table gives the largest gap to doing nothing
  in any month from July 2025 to the election.
- Two extra strategies were added because the six asked for did not settle the questions: (g) a wrecker, to find
  out whether the election can be lost at all, and (h) "tax early, please late", which turned out to be dominant.

## Strategies at a glance (election in July 2029; the majority is 326)

| Strategy | Approval Jun 2029 | Centre-left seats | Government after | Balance Jun 2029 £bn/yr | Debt % GDP | Unemployment | Bills passed |
|---|---|---|---|---|---|---|---|
| (a) Nothing, first answers | 29.8% | 344 | Centre-left | -189 | 105.4 | 4.8% | 0 |
| (b) Nothing, second answers | 29.8% | 344 | Centre-left | -191 | 105.5 | 4.9% | 0 |
| (c) Crowd-pleaser | 32.1% | 377 | Centre-left | -235 | 106.8 | 4.7% | 21 |
| (d) Austerity | 28.5% | 326 (exactly) | Centre-left | -93 | 101.6 | 5.5% | 32 |
| (e) Reformer | 29.8% | 344 | Centre-left | -182 | 103.6 | 4.7% | 9 |
| (f1) Basic rate 30% in Feb 2025 | 29.8% | 344 | Centre-left | -157 | 105.0 | 4.8% | 1 |
| (f2) Health cut by a quarter in Feb 2025 | 26.7% | 284 | Coalition CL+Lib+Green+SNP+PC (387) | -159 | 106.4 | 4.7% | 1 |
| (g) Wrecker | 21.4% | 156 | Centre-right+populist right+NI | +47 | 97.6 | 4.9% | 5 |
| (h) Tax early, please late | 32.1% | 383 | Centre-left | -166 | 101.0 | 3.9% | 17 |

## Conclusions

### Is the election winnable and losable?

- **Winnable by default.** Doing nothing (answering every question with its first answer, or its second) keeps 344
  seats in July 2029 on 29.7% of the vote against the centre-right's 25.3%. Approval drifts down by about one point
  a year (33.9% to 29.8%) from time in office; nothing else threatens it.
- **Losable only by trying.** Austerity that cuts the deficit by half holds exactly 326 seats (a knife-edge majority);
  a quarter off health spending loses the majority (284 seats) but the game keeps the player in office through a
  five-party coalition, so it is not a loss. Only the wrecker (health -50%, basic rate 35%, VAT 30%, benefits -30%,
  education -40%) loses office: 156 seats, approval 21%.
- **The range is narrow.** Every strategy that is not deliberate wrecking ends between 28.5% and 32.1% approval and
  between 326 and 383 seats. A whole term of crowd-pleasing is worth about +2.3 points.
- **Pleasing voters and sane finances: one strategy dominates.** (h) raises the basic rate to 25% and VAT to 23% in
  February 2025, waits, then from 2027 spends its capital on popular policies whose reactions last (EV grant,
  insulation, universal Winter Fuel Payment, free prescriptions, social housing, cheap buses, free school meals, more
  for the NHS). It wins more seats than the pure crowd-pleaser (383 against 377) with a deficit £69bn a year smaller
  and debt 6 points lower. The reason is structural: voters judge their income against its average over about a year
  (`income_memory` in `models/uk/politics.toml`, `/ 12.0`), so a tax rise is forgotten within one to two years, while
  each real-life policy's reaction (`standing_*` in `models/uk/policies.toml`) is a level that lasts as long as the
  policy. f1 shows it starkly: a basic rate of 30% costs 2.4 points in July 2025 and nothing at all by January 2028
  (+0.05 points against doing nothing at the election). Austerity, which keeps raising taxes and cutting spending
  through the term, is punished; doing the pain once, early, is not.

### Political capital

- **Earned:** about 50 in 2025 (the first-year bonus), then 29 to 40 a year (2.3 to 3.3 a month), because the
  rating sits between 28% and 34% and `capital_from_support` pays only from 25% upwards. Plus the 40 at the start.
- **Bills a year:** small changes (a point of tax, 3% to 5% of a spending line, about 6 each) allow 5 to 7 a year
  after 2025 (austerity passed 32 over the term, 14 of them in 2025); real-life introductions (20 to 65 each) allow
  one or two a year (the reformer passed 9 in five years, only 1 a year from 2027). In the check's scripted term
  (client/tests/full_term.gd) the decisions had to be spread out to fit: a first draft lost three bills to capital.
- **Binding or wasted?** For any active player capital is the binding limit from the first year on. A passive player
  reaches the cap of 100 in early 2026 and wastes 28 to 39 a year after that (128 over the term).
- **Prices.** The cost is 5 plus 60 x weight x the share of the range moved, so the price follows the width of the
  range, not the size of the decision:
  - Effectively unaffordable after year one: anything at 65 (cannabis legal and taxed, strict rent controls, free
    school meals for all pupils at the full step, the EV grant or insulation or social housing at their maxima),
    which is two years of income; the full move of fuel duty to 100p costs 33 and to 0p 37.
  - Trivially cheap for what they do: the macro levers. A quarter off NHS spending costs 12.5 and half costs 20;
    benefits -30% costs 14; the basic rate +15 points costs 14. Each of those moves the economy and the vote more
    than any real-life policy, yet costs less than an EV grant at £3,000 (20) or the Winter Fuel Payment made
    universal (35). The spending levers' range is 0 to twice 2024, so 25% of a line is only an eighth of the range.
  - Repealing costs the same as introducing (the EV grant at £2,500: 17.5 each way).
- **No small-bill exploit:** the 5 per bill makes many small bills dearer than one big one. The real exploits are the
  cheap macro levers above, free answers to questions (the pay claim or emergency NHS money move billions at no
  capital), and the coalition jump below.

### Do the real-life policies matter? (table below)

- **Too strong:** fuel duty. 0p gives +2.7 points of approval for the whole term, 100p -3.8 points: three to four
  times any other policy, more than a 10-point basic rate rise costs at the election (nothing) and as much as the
  whole crowd-pleaser programme. Motorists are 80% of adults, and `standing_fuel_duty` charges 0.004 of utility a
  penny. Abolishing fuel duty and raising income tax early to pay for it is a straightforward exploit.
  Petrol ban year moves the electric share by +28 points (2028) or -40 points (2040), the largest indicator move of
  all, and the young by 2.2 points. Alcohol duty at double: -0.9 points; alcohol deaths -21%.
- **Too weak to notice (under about 0.2 points and no visible indicator move):** the sugar levy at either end
  (+0.07, -0.12; nothing moves), the bus fare cap at £1 (+0.09), the Winter Fuel Payment either way (±0.2, no
  incomes move, as the guide warns), the prescription charge (±0.3 points but nothing on the board moves), cannabis
  law (-0.12; crime -1.5%), drinking age 16 (-0.11). Sentencing (±0.12) and planning (-0.1 at both ends) barely move
  approval, but their indicators show (prisoners ±14%, homes built ±13%).
- **About right:** EV grant, insulation, social housing (+0.6 at £500m a month, the strongest of the spending
  policies), tuition fees, visa threshold, rent controls, tobacco duty, free school meals: 0.15 to 0.6 points with a
  visible indicator.
- **Planning rules lose approval at both ends** (-0.10 very restrictive, -0.12 very liberal): the owners' loss
  outweighs the renters' gain in the liberal direction and the young's loss in the other, so liberalising, the
  policy with the biggest economic effect of its area (+13% homes, deficit down 5%), is never rewarded.

### Do the groups differ enough?

- At the start the groups span pensioners 21% to the young 49% (the 2024 vote). Under every strategy that ordering
  never changes: pensioners stay lowest, the young highest.
- Strategies move the groups mostly together: the spread of changes against doing nothing is 0.9 points (b), 1.8
  (c: pensioners +1.7 to low incomes +3.5), 1.3 (d), 1.4 (e), 0.1 (f1), 1.2 (f2), 4.3 (g). Over the term under (a)
  every group falls, London most (-5.4) and pensioners least (-3.0).
- Single policies do separate them: the petrol ban at 2040 costs the young 2.2 points while the national figure
  rises 0.1; a drinking age of 21 costs the young 1.8; visa threshold and sentencing set pensioners against the young
  (±0.4 to 0.9). So choices are interesting at the level of one policy, but the economy and taxes, which dominate
  the vote, move everyone alike.

### Pacing

- Questions: 13 in five years under (a) (2 in 2025, 4, 4, 1 in 2028, 2 in 2029); situations begin or end 1 to 2
  times a year. Approval moved by half a point or more in a single month in at most one or two months a year, under
  every strategy but the shocks.
- Dead stretches: 9 months with no question and no situation change (August 2028 to April 2029) under (a), 12 months
  under (c). 2028 has one question at most.
- Repetition: the NHS winter crisis comes three times (July 2027, 2028, 2029) and full prisons three times; once a
  waiting list record is set it stays (every strategy but (c) and (h) ends with "record waiting list", and health
  strain from mid-2029 even with doing nothing).
- Some situations become wallpaper: "emissions above the path to net zero" from 2026 and "debt above a year's
  output" from 2027 never end under most strategies.

### Broken, absurd or exploitable

1. **The coalition jump.** When the centre-left loses its majority but forms a coalition (f2), `government_support`
   becomes the sum of the partners' intention: the centre of the board jumps from 26.7% to 55.8%, Scotland's
   approval to 79%, and `capital_earned` to its maximum of 8 a month (51 in the next 12 months against 19 before).
   Losing the majority pays.
2. **Tax rises are free in the long run** (income memory of about a year, above); policy reactions are permanent.
   This makes "tax early, please late" dominant.
3. **Pensioner poverty is a cliff.** Many pensioner households sit at the 60%-of-median line: a basic rate of 30%
   (which lowers the median) cuts pensioner poverty from 27.7% to 18.7% in one month; austerity and the health cut
   do the same around month 12 to 18; small perturbations in other runs flip it by 7 to 8 points in a single month
   (in July 2029). Overall poverty also jumps by ±1.3 points from planning rules or the visa threshold. These are
   bunching artefacts, not policy effects.
4. **The economy heals too fast.** The wrecker's unemployment reaches 15.9% in January 2026 and is back to 4.9% by
   mid-2029 with health spending still halved, and the budget goes from -£149bn to a £47bn surplus. Nothing runs
   away; rather, nothing stays broken except approval.
5. **A 10-point tax rise first worsens the deficit** (-£170bn a year in July 2025 against -£162bn doing nothing),
   because of the recession it causes (growth -5.8% annualised in February 2025), and by 2029 improves it by only
   £32bn a year against a static yield of £50bn or more.
6. **Approval barely moves**: the whole space of sensible play is 28.5% to 32.1%; one month's change is almost always
   under half a point, so the centre's figure and its arrow carry little news.
7. **Bills of one month are charged in different orders in the game and in `polisim play`.** Through the bridge the
   bill made first is charged first; through `polisim play` the last made is (repro: start
   `polisim play models/uk/scenarios/2025.toml`, `set sentencing 4`, `set ev_grant 2500`, `step`,
   `show capital_spent ev_grant sentencing`: the grant passes and sentencing is refused, 17.5 spent; through the
   bridge the same two bills pass sentencing and refuse the grant, 29 spent). This does not affect the strategies
   above (none had a bill refused), but the runner and the game disagree on which bill is refused.
8. Values pinned at a limit: none in these runs except political capital at 100 for the passive strategies.

## Tuning recommendations, in order

1. **Make income effects last** (`models/uk/politics.toml`, `state.income_memory`, and the template that writes it):
   either compare real income with its level at the last election, as unemployment (`voter_jobs`) and the issues
   (`voter_services`) already do, or lengthen the memory from 12 to about 36 months (`/ 12.0` to `/ 36.0`). Why:
   removes the dominant "tax early" strategy and makes f1's 10-point rise cost something at the election.
2. **Cut the fuel duty reaction by about three quarters** (`tools/uk/template/policies.toml`,
   `var.standing_fuel_duty`: 0.004 to 0.001 a penny for a rise, 0.002 to 0.0005 for a cut). Why: ±47p should be
   worth about 1 point, in line with alcohol duty, not 3 to 4.
3. **Price the macro levers by their weight** (the lever tables that `tools/uk` writes into
   `models/uk/functions.toml`, `households.toml` and `calibration.toml`): `capital_weight` 3 for `spending_health`,
   `spending_education`, `benefits_bill` and `spending_social_care` (a quarter off health from 12.5 to 27.5), and 2 for
   `basic_rate`, `vat_rate` and `ni_main_rate` (a point of basic rate from 5.6 to 6.2; ten points from 11 to 17). Why:
   the biggest decisions are the cheapest today.
4. **Re-centre capital income on the ratings the model produces** (`tools/uk/template/capital.toml`,
   `var.capital_earned`): `(government_support - 0.25) / 0.2` to `(government_support - 0.20) / 0.20`, and
   `capital_monthly` 1 to 1.5. Why: ratings sit at 28% to 34%, so today the support term pays 0.75 to 2.25 a month
   and an active government passes one introduction a year; this gives about 4 a month, two to three introductions
   a year. Keep `capital_most` 100 (the passive player wastes it, which is fine).
5. **Base capital on the player's own bloc** (`var.capital_earned`: `government_support` to the centre-left's
   `vote_intention`), and show that bloc's share at the centre after a coalition. Why: removes the coalition jump.
6. **Lower the price of the dearest introductions**: `capital_weight` for `rent_controls` and `cannabis_law` 1.0 to
   0.6 (65 to 41 for the full step), `free_school_meals` 0.5 stays; and let a repeal cost half an introduction (an
   engine rule, so for later). Why: 65 is two years of capital.
7. **Strengthen the invisible policies or show their effect**: `standing_sugar_levy` 0.005 to 0.015,
   `standing_bus_fare_cap` x2, and give the Winter Fuel Payment and free school meals household incomes (a known
   limit). Why: under 0.2 points and nothing on the board moves.
8. **Planning rules**: halve the home owners' penalty in `standing_planning` so that liberalising is net positive for
   approval (renters and the young gain), as its effect on housing and the deficit deserves.
9. **Pacing** (`models/uk/dilemmas.toml`): give the NHS winter crisis and full prisons a cool-down of two years, and
   add one or two chance questions for 2028; consider ending "emissions above path" and "debt above output" as
   flags that need no reminder after a year.
10. **Smooth the pensioner poverty cliff** (in `tools/uk`'s household build): spread state pension amounts in the
    synthetic households so that the 60%-of-median line does not cut through a block of identical pensioners.

## The real-life policies, one at a time

Each set at the end of its range in July 2025 (bill cost as charged), against doing nothing; the gap is the largest
in any month to July 2029. Indicators are percent changes, or points for rates; "budget balance" is the change in
the deficit as a share of it (the deficit is about £150bn to £190bn a year, so 5% is about £8bn a year). NHS
treatments and the waiting list are left out of the indicator columns: they move by ±5% only because the NHS winter
question comes a month earlier or later. Pensioner poverty is left out (the cliff above).

| Policy at | Bill cost | Approval (largest gap to doing nothing, Jul 2025 to Jul 2029) | Groups moved most | Largest indicator moves |
|---|---|---|---|---|
| drinking_age=16 | 29.0 | -0.11 pts | pensioners -0.38, young +0.25 | crime_incidents +1.0%; alcohol_deaths +1.0%; output_growth -0.4 pts; budget balance +1.7% |
| drinking_age=21 | 41.0 | -0.54 pts | young -1.80, renters -0.85 | crime_incidents -1.6%; alcohol_deaths -1.5%; child_poverty_rate +0.1 pts; budget balance -0.1% |
| sentencing=0 | 35.0 | -0.11 pts | young +0.50, pensioners -0.41 | prison_population -14.0%; crime_incidents +1.8%; child_poverty_rate -0.1 pts; budget balance +0.2% |
| sentencing=4 | 35.0 | +0.12 pts | young -0.49, pensioners +0.42 | prison_population +14.0%; crime_incidents -1.8%; child_poverty_rate +0.1 pts; budget balance -0.2% |
| cannabis_law=2 | 65.0 | -0.12 pts | young +0.74, pensioners -0.65 | crime_incidents -1.5%; debt_to_gdp -0.1 pts; child_poverty_rate -0.1 pts; budget balance +0.6% |
| alcohol_duty=0.5 | 25.0 | +0.46 pts | london +0.53, high_income +0.53 | alcohol_deaths +10.6%; debt_to_gdp +0.7 pts; crime_incidents +0.6%; budget balance -5.1% |
| alcohol_duty=2 | 45.0 | -0.87 pts | london -0.99, high_income -0.98 | alcohol_deaths -21.3%; crime_incidents -1.2%; debt_to_gdp -1.1 pts; budget balance +7.0% |
| tobacco_duty=0.5 | 25.0 | +0.21 pts | low_income +0.27, out_of_work +0.27 | smoking_prevalence +1.0 pts; output_growth -0.4 pts; debt_to_gdp +0.4 pts; budget balance -3.2% |
| tobacco_duty=2 | 45.0 | -0.36 pts | low_income -0.46, out_of_work -0.45 | smoking_prevalence -2.0 pts; public_receipts +0.6%; healthy_life_expectancy +0.5%; budget balance +4.1% |
| sugar_levy=0 | 25.0 | +0.07 pts | low_income +0.16, lone_parents +0.13 | child_poverty_rate +0.1 pts; debt_to_gdp +0.0 pts; poverty_rate +0.0 pts; budget balance -0.2% |
| sugar_levy=3 | 45.0 | -0.12 pts | low_income -0.31, lone_parents -0.24 | child_poverty_rate +0.1 pts; public_receipts +0.0%; healthy_life_expectancy +0.0%; budget balance +0.3% |
| prescription_charge=0 | 34.7 | +0.30 pts | low_income +0.66, out_of_work +0.54 | debt_to_gdp +0.1 pts; public_receipts -0.1%; child_poverty_rate +0.0 pts; budget balance -0.4% |
| prescription_charge=20 | 35.3 | -0.31 pts | low_income -0.67, out_of_work -0.55 | child_poverty_rate +0.1 pts; debt_to_gdp -0.1 pts; public_receipts +0.0%; budget balance +0.3% |
| fuel_duty=0 | 36.8 | +2.69 pts | wales +3.01, north +3.00 | household_emissions +9.5%; ev_share -2.7 pts; debt_to_gdp +2.5 pts; budget balance -13.8% |
| fuel_duty=100 | 33.2 | -3.76 pts | north -4.26, wales -4.25 | household_emissions -7.6%; ev_share +2.4 pts; emissions -1.7%; budget balance +11.4% |
| ev_grant=6000 | 65.0 | +0.37 pts | young +0.99, renters +0.51 | ev_share +4.5 pts; debt_to_gdp +0.8 pts; household_emissions -0.4%; budget balance -5.4% |
| bus_fare_cap=1 | 20.0 | +0.09 pts | young +0.28, low_income +0.26 | child_poverty_rate +0.1 pts; debt_to_gdp +0.1 pts; poverty_rate +0.0 pts; budget balance -0.3% |
| bus_fare_cap=5 | 50.0 | -0.25 pts | young -0.84, low_income -0.78 | debt_to_gdp -0.0 pts; child_poverty_rate +0.0 pts; output_growth -0.0 pts; budget balance +0.3% |
| insulation_programme=400000000.0 | 65.0 | +0.30 pts | low_income +0.96, young +0.78 | household_emissions -1.1%; output_growth +0.5 pts; public_receipts +0.2%; budget balance -2.4% |
| petrol_ban_year=2028 | 15.0 | -0.22 pts | midlife -0.36, young +0.28 | ev_share +28.0 pts; household_emissions -1.8%; emissions -0.5%; budget balance -0.4% |
| petrol_ban_year=2040 | 55.0 | +0.09 pts | young -2.23, midlife +0.73 | ev_share -40.0 pts; household_emissions +2.0%; emissions +0.5%; budget balance +0.5% |
| tuition_fee_cap=0 | 42.0 | +0.24 pts | young +1.14, renters +0.47 | output_growth -0.3 pts; child_poverty_rate -0.2 pts; median_income -0.1%; budget balance +1.5% |
| tuition_fee_cap=15000 | 28.0 | -0.40 pts | young -1.53, renters -0.70 | output_growth +0.2 pts; child_poverty_rate +0.1 pts; median_income +0.1%; budget balance -0.8% |
| free_school_meals=2 | 65.0 | +0.16 pts | lone_parents +0.37, parents +0.28 | school_attainment +0.7 pts; output_growth +0.3 pts; child_poverty_rate +0.2 pts; budget balance -1.3% |
| planning_rules=0 | 35.0 | -0.10 pts | young -0.49, london -0.25 | dwellings -13.4%; homes_built -13.1%; poverty_rate -1.4 pts; budget balance -4.7% |
| planning_rules=4 | 35.0 | -0.12 pts | young +0.40, midlife -0.24 | dwellings +13.5%; homes_built +13.1%; debt_to_gdp -1.2 pts; budget balance +4.7% |
| social_housing=500000000.0 | 65.0 | +0.60 pts | low_income +1.41, young +1.10 | homes_built +15.7%; output_growth +0.6 pts; public_receipts +0.3%; budget balance -3.0% |
| rent_controls=2 | 65.0 | +0.15 pts | young +0.75, low_income +0.54 | dwellings -5.4%; homes_built -5.2%; debt_to_gdp +0.5 pts; budget balance -1.9% |
| winter_fuel_payment=0 | 35.0 | -0.20 pts | pensioners -0.65, wales -0.26 | child_poverty_rate -0.1 pts; output_growth -0.0 pts; dwellings -0.0%; budget balance +0.2% |
| winter_fuel_payment=2 | 35.0 | +0.21 pts | pensioners +0.66, wales +0.27 | child_poverty_rate +0.1 pts; output_growth +0.1 pts; dwellings +0.1%; budget balance -0.6% |
| visa_threshold=20000 | 33.0 | -0.09 pts | young +0.49, pensioners -0.35 | net_migration_annual +13.3%; poverty_rate -1.3 pts; output_growth +0.4 pts; budget balance -2.4% |
| visa_threshold=60000 | 37.0 | +0.39 pts | pensioners +0.85, young -0.55 | net_migration_annual -14.7%; median_income +0.5%; net_income_average +0.5%; budget balance +0.8% |

## After S13.7

Played again on 2026-11-15 with the decisions of `docs/S13-PLAN.md`, "S13.7: what the playtest
changes", in the model: voters remember half of their income change from the last election;
the big spending lines weigh 3 in capital and the main tax rates 2 (cannabis law and rent
controls 0.6); capital is earned at 1.5 a month and up to 5 more on the player's own party's
rating, centred on 20% to 40%; fuel duty's reaction is a quarter of what it was and seven
weak policies react more; the NHS winter crisis and full prisons wait two years before they
come again; two chance questions from 2028 (fuel protests, small boats) and six situations for
the new indicators; and the 2025 scenario's own wear of office, `vote_wear_effect` -0.025 a
year beyond the first six months (nil in the base month).

Method as before, with one difference: the strategies were replayed through the game's own
`Session` (a scratch runner against `polisim-core`, since deleted), each bill made in the
month listed above and, if the capital or the Commons would not take it, again each month
until it passed. Under the old model this runner reproduces the first table to the seat for
every strategy except austerity (323 seats rather than 326) and the wrecker (151 rather than
156), whose bills it passed in slightly different months, and it counts bills passed to July
2029 only. Capital earned, spent and wasted
at the cap are from January 2025 to June 2029, beside the same runner's figures for the old
model.

### Strategies at a glance, after S13.7 (election in July 2029; the majority is 326)

| Strategy | Approval Jun 2029 (before) | Centre-left seats (before) | Government after | Balance Jun 2029 £bn/yr | Debt % GDP | Unemployment | Bills passed | Capital earned / spent / wasted (before) |
|---|---|---|---|---|---|---|---|---|
| (a) Nothing, first answers | 28.7% (29.8%) | 330 (344) | Centre-left | -190 | 105.4 | 4.8% | 0 | 248 / 0 / 188 (163 / 0 / 103) |
| (b) Nothing, second answers | 28.3% (29.8%) | 323 (344) | CL+SNP | -191 | 105.4 | 4.8% | 0 | 242 / 0 / 182 (159 / 0 / 99) |
| (c) Crowd-pleaser | 32.3% (32.1%) | 382 (377) | Centre-left | -235 | 106.9 | 4.7% | 17 | 277 / 230 / 0 (185 / 221 / 0) |
| (d) Austerity | 26.4% (28.4%) | 274 (323) | CL+Lib+Grn+SNP+PC | -92 | 101.8 | 5.4% | 29 | 220 / 193 / 0 (141 / 169 / 0) |
| (e) Reformer | 29.3% (29.8%) | 337 (344) | Centre-left | -182 | 103.6 | 4.7% | 8 | 249 / 163 / 26 (157 / 163 / 0) |
| (f1) Basic rate 30% in Feb 2025 | 27.4% (29.8%) | 304 (344) | CL+Grn+SNP+PC | -158 | 105.0 | 4.8% | 1 | 222 / 17 / 145 (151 / 11 / 80) |
| (f2) Health cut by a quarter in Feb 2025 | 25.2% (26.7%) | 247 (284) | CL+Lib+Grn+SNP+PC | -160 | 106.4 | 4.8% | 1 | 195 / 28 / 108 (114 / 13 / 41) |
| (g) Wrecker | 16.3% (21.2%) | 62 (151) | Centre-right | +33 | 102.4 | 10.6% | 5 | 150 / 175 / 0 (71 / 82 / 0) |
| (h) Tax early, please late | 30.7% (32.2%) | 361 (383) | Centre-left | -167 | 101.0 | 3.9% | 13 | 243 / 207 / 32 (163 / 194 / 2) |

### The real-life policies that changed

Measured as before (each at an end of its range from July 2025, the largest gap to doing
nothing in any month to the July 2029 election; the figure before S13.7 in brackets). The bill
cost is what the game charges, 5 + 60 x weight x the share of the range moved; the first table's
costs for the drinking age, fuel duty and the visa threshold do not follow that formula and
are not repeated here.

| Policy at | Bill cost | Approval | Groups moved most | Largest indicator moves |
|---|---|---|---|---|
| drinking_age=16 | 17.0 | -0.33 pts (-0.11) | pensioners -1.29, young +0.49 | crime_incidents +1.0% |
| cannabis_law=2 | 41.0 (65.0) | -0.29 pts (-0.12) | young +2.05, pensioners -1.88 | crime_incidents -1.5% |
| sugar_levy=0 | 9.0 | +0.21 pts (+0.07) | low_income +0.59, lone_parents +0.44 | healthy life -0.04 years |
| sugar_levy=3 | 13.0 | -0.41 pts (-0.12) | low_income -1.15, lone_parents -0.87 | healthy life +0.09 years (+0.03) |
| prescription_charge=0 | 13.9 | +0.53 pts (+0.30) | low_income +1.15, out_of_work +0.95 | healthy life +0.09 years (+0.02) |
| prescription_charge=20 | 14.1 | -0.53 pts (-0.31) | low_income -1.15, out_of_work -0.95 | healthy life -0.09 years (-0.02) |
| fuel_duty=0 | 43.1 | +1.46 pts (+2.69) | north +1.65, wales +1.59 | household_emissions +9.5%; ev_share -2.6 pts |
| fuel_duty=100 | 38.9 | -1.58 pts (-3.76) | north -1.79, wales -1.74 | household_emissions -7.6%; ev_share +2.4 pts |
| bus_fare_cap=1 | 9.5 | +0.38 pts (+0.09) | young +1.26, low_income +1.17 | none |
| bus_fare_cap=5 | 18.5 | -0.30 pts (-0.25) | young -1.00, low_income -0.92 | none |
| planning_rules=0 | 35.0 | -0.11 pts (-0.10) | young -0.51, london -0.26 | homes_built -13.1% |
| planning_rules=4 | 35.0 | +0.14 pts (-0.12) | young +0.57, london +0.31 | homes_built +13.1% |
| rent_controls=2 | 41.0 (65.0) | +0.15 pts (+0.15) | young +0.75, low_income +0.54 | homes_built -5.2% |
| winter_fuel_payment=0 | 35.0 | -0.42 pts (-0.20) | pensioners -1.42, wales -0.56 | none |
| winter_fuel_payment=2 | 35.0 | +0.45 pts (+0.21) | pensioners +1.49, wales +0.59 | none |

Every other row moved by 0.03 points or less.

### The conclusions, again

**Is the election winnable and losable?** Changed. Doing nothing now keeps 330 seats with the
first answers and 323 with the second, a hung parliament in which the centre-left governs with
the SNP: the majority is in doubt, not safe. The reasons are the 2025 scenario's own wear of
office (without it doing nothing gives 363 seats, more than before, because real incomes grow
over the term and voters now remember that too) and the memory of income. Losing office still
takes trying: austerity (274 seats), a 30% basic rate (304) and a quarter off health (247) all
lose the majority but keep the centre-left in office through a coalition; only the wrecker
loses it (62 seats). The range of sensible play is wider, 25.2% to 32.3% at the election
against 26.7% to 32.2%, and 247 to 382 seats against 284 to 383.

**One strategy dominates?** Changed, but not as hoped. "Tax early, please late" no longer wins:
361 seats against the crowd-pleaser's 382, because a tax rise early in the term now costs
something on polling day (f1's 30% basic rate costs 26 seats at the election, against none
before). What wins now is plain spending: the crowd-pleaser runs the largest deficit (£235bn a
year) and wins the most seats, while austerity, which halves the deficit, loses the majority.
Sound finances are still punished and borrowing is not: voters in the model do not weigh the
deficit or debt at all. That is still wrong, and it needs a voter term for the public
finances or a market reaction to debt, which no decision of this stage covers.

**Political capital.** Changed. Earned about 4 to 5 a month (220 to 277 from January 2025 to
June 2029 for every strategy but the health cut and the wrecker, against 141 to 185), so the
reformer and "tax early" end
the term with capital to spare and the crowd-pleaser holds 87 in June 2029. Big decisions now
cost more than small ones: a quarter off the NHS 27.5 (12.5 before), a point on the basic rate
6.2, ten points 17; the dearest introductions 41 (65 before). The coalition jump is gone where
it mattered: after f2's election the governing blocs' share is 56.2% but the centre of the
board and capital follow the centre-left's own 34.2% (its time in office restarts with the new
coalition, so it recovers). Still true: a passive player wastes most of what is earned (188
under (a), more than before), and answers to questions remain free.

**Do the real-life policies matter?** Mostly resolved. Fuel duty's direct reaction is a quarter
of what it was, yet it remains the strongest policy (+1.46 points abolished, -1.58 at 100p),
because most of what is left is what the duty does to prices and real incomes, which voters now
remember to the election; it is about twice as strong as alcohol duty at the top of the
range and three times at the bottom, against four to six times before.
The soft drinks levy, the prescription charge, the bus fare cap, the Winter Fuel Payment,
cannabis law and a drinking age of 16 now move national approval by 0.2 to 0.5 points and
their most affected group by 0.6 to 2.1 points; the levy and the charge move healthy life by
0.09 years. Still invisible on the board: the Winter Fuel Payment and the bus fare cap move no
indicator (the households hold no Winter Fuel Payment and the model no bus journeys).
Liberal planning is now a small gain (+0.14) rather than a loss.

**Do the groups differ enough?** Little changed. Pensioners are still lowest and the young
highest under every strategy, and the economy still moves every group together. Single
policies separate them more than before (cannabis law: the young +2.1, pensioners -1.9).

**Pacing.** Partly resolved. Under (a) thirteen questions by the election (2, 4, 3, 2 and 2 a
year, against 1 in 2028 before); the NHS winter crisis comes twice and full prisons twice,
not three times each; the longest stretch with no question and no situation change is 8 months
(9 before). The new situations come with the policies that
cause them (a tenth off the police brings a crime wave that ends a year after the money is
restored; very restrictive planning a housing shortage; a £20,000 visa threshold high net
migration, a £60,000 one falling net migration; a health cut falling healthy life; liberal
planning a building boom), but none comes under doing nothing. Unchanged: "debt above a
year's output" and "emissions above the path" stay on for most of the term under most
strategies.

**Broken, absurd or exploitable.**

1. The coalition jump: resolved for the centre and for capital (above). The Parliament sheet
   still shows the governing blocs' share, as it should.
2. Tax rises free in the long run: resolved in part (f1 costs 26 seats), but see "One strategy
   dominates": deficits are free instead.
3. The pensioner poverty cliff: not changed (left for later in the plan: it needs the
   households rebuilt).
4. The economy heals too fast: not changed. The wrecker's unemployment is 10.6% in June 2029
   only because its health cut, now dearer (50 rather than 20), could not be paid for until
   October 2028, so its slump falls just before the election.
5. A 10-point tax rise first worsens the deficit: not changed.
6. Approval barely moves: a little better. The range of play is about 7 points rather than 5,
   but a month's change is still almost always under half a point.
7. The runner and the game: fixed. The report's two-bill example gives the same result in both
   (sentencing passes, the grant is refused); the real difference was a lever changed twice in
   one month, which `polisim play` kept in its first place while the game moves it to the end.
   `polisim play` now does what the game does (`crates/cli/src/play.rs`, with a test).
8. Values pinned at a limit: political capital at 100 for the passive strategies, now sooner
   (January 2026 under (a)).

## After S13.8

Played a third time on 2026-11-15 with the decisions of `docs/S13-PLAN.md`, "S13.8: the
public finances matter", in the model:

- **Lenders.** New gilts cost 0.75 points more for each point of GDP that borrowing, averaged
  over a year, runs above January 2025's 5.1%, and as much less below it. The premium is capped
  at two points and the discount at half a point (`models/uk/finances.toml`). It reaches debt
  interest through the average rate on the debt. The model has no other interest-rate path to
  households or firms, so it stops there.
- **Voters.** Voters weigh that borrowing against the last election, on a curve that is mild
  to a point of GDP and steep beyond it. Pensioners, home owners and high incomes weigh it
  most. It shows as the group popups' sixth driver, "The public finances".
- **The crisis.** "Lenders refuse the gilts" opens once smoothed borrowing is 1.2 points
  above the start, from the thirteenth month. Its three answers are an emergency budget,
  holding course at two points more, or asking the Bank to buy.
- **Situations.** "Lenders' confidence" comes on more than a point below the start.
  "Debt above a year's output" becomes "Debt rising fast": seven points of GDP above the
  start rather than above 100%.
- **The board.** The gilt yield is an indicator in Economy.

Lenders and voters are switched on by the 2025 scenario's `[params]`
(`lender_premium_effect` 0.75, `vote_finances_effect` 1) and are nil in the base month.
`vote_wear_effect` is unchanged at -0.025. The method is as in "After S13.7": the same
scratch runner, since deleted, with every question given its first answer (so the
crowd-pleaser answers the crisis with the emergency budget).

### Strategies at a glance, after S13.8 (election in July 2029; the majority is 326)

The approval columns are Jan 2026 / Jan 2027 / Jun 2029. Figures in brackets are after
S13.7.

| Strategy | Approval | CL seats (after S13.7) | Government after | Balance Jun 2029 £bn/yr | Debt % GDP | Gilt yield Jun 2029 | Unemployment | Bills passed | Capital earned / spent / wasted | Lenders refuse |
|---|---|---|---|---|---|---|---|---|---|---|
| (a) Nothing, first answers | 32.7 / 31.4 / 28.5% | 325 (330) | CL+SNP | -192 | 105.5 | 4.58% | 4.8% | 0 | 245 / 0 / 185 | no |
| (b) Nothing, second answers | 32.7 / 31.4 / 28.1% | 315 (323) | CL+SNP | -192 | 105.5 | 4.54% | 4.8% | 0 | 241 / 0 / 181 | no |
| (c) Crowd-pleaser | 34.1 / 32.2 / 28.3% | 312 (382) | CL+SNP | -225 | 107.4 | 5.06% | 4.9% | 17 | 249 / 230 / 0 | Aug 2027 |
| (d) Austerity | 30.6 / 29.7 / 28.1% | 314 (274) | CL+SNP | -89 | 101.7 | 3.70% | 5.4% | 29 | 229 / 193 / 0 | no |
| (e) Reformer | 32.5 / 31.4 / 29.2% | 336 (337) | Centre-left | -183 | 103.6 | 4.37% | 4.7% | 8 | 248 / 163 / 25 | no |
| (f1) Basic rate 30% in Feb 2025 | 30.1 / 29.5 / 27.6% | 309 (304) | CL+SNP+PC | -157 | 104.9 | 3.97% | 4.8% | 1 | 223 / 17 / 146 | no |
| (f2) Health cut by a quarter in Feb 2025 | 27.9 / 27.1 / 25.4% | 249 (247) | CL+Lib+Grn+SNP+PC | -160 | 106.4 | 4.07% | 4.8% | 1 | 195 / 28 / 108 | no |
| (g) Wrecker | 26.8 / 25.2 / 18.3% | 101 (62) | CR+PopR | +38 | 100.5 | 3.70% | 7.5% | 5 | 152 / 175 / 0 | no |
| (h) Tax early, please late | 31.2 / 31.7 / 31.0% | 364 (361) | Centre-left | -165 | 100.8 | 3.86% | 3.9% | 13 | 248 / 207 / 34 | no |

The gilt yield in January 2025 is 4.20% under every strategy.

The crowd-pleaser's other answers to the crisis do worse:
- **Hold course:** 276 seats. The yield goes past 7%, and inflation is 4.2% in January 2028.
- **The Bank buys:** 247 seats. Inflation is 5.3% in January 2028, and the slump that follows
  brings a bank rescue in July 2028.

### The conclusions, a third time

**Borrowing is no longer free.**
- The crowd-pleaser leads doing nothing in the polls by 1.4 points after one year and 0.8
  after two.
- Smoothed borrowing passes 1.2 points above the start in August 2027, and lenders refuse
  the gilts.
- The emergency budget is resented for two years, and by the election it polls 28.3% against
  doing nothing's 28.5%: 312 seats against 325.
- Austerity, which halves the deficit, gains from lenders' confidence (from January 2028)
  and from voters' view of the finances. It ends near the line at 314 seats, not 274.
- The paid-for programme wins: "tax early, please late" (364) and the reformer (336) are the
  only strategies with a majority of their own. The wrecker still loses office.
- The earlier finding stands that a tax rise early in the term now costs something at the
  election: f1 holds 309.

**Doing nothing.**
- 325 seats with the first answers and 315 with the second. Both are a hung parliament in
  which the centre-left governs with the SNP.
- Doing nothing also borrows about half a point more by 2029, which costs a little. The wear
  of office was left as it was because the result is within 320 to 335.

**What is still wrong.**
- The curve is steep past a point of GDP, and most of the crowd-pleaser's loss comes from
  there and from the emergency budget's two years. A strategy that borrows slightly less
  (under the 1.2-point line) would escape both. Judgement, not evidence, sets where the line
  is.
- Austerity wins no more seats than doing nothing, though its deficit is half as large:
  voters reward a fall in borrowing at about a quarter of the rate they punish a rise, and its
  cuts still cost through services and jobs.
- The lenders' premium moves debt interest slowly. The average rate follows new gilts over
  fourteen years, so a crowd-pleaser's extra 0.86 points on new gilts adds only about 0.1
  points to the average rate by 2029. Nothing else feels it: the model has no Bank Rate and
  no mortgages, and investment reads no rate.
- The approval range is still narrow (25.4% to 31.0% for every strategy but the wrecker),
  and a month's change is still almost always under half a point.

**Pacing.** Under (a) there are still 2, 4, 3, 2 and 2 questions a year, and the crisis comes
only to heavy borrowers. "Debt rising fast" now comes on in late 2028 under doing nothing
rather than staying on from 2027. The longest stretch with nothing new is 6 months, from 8.

## After S14.5

Played a fourth time on 2026-11-16 with stage S14.5 of `docs/S14-PLAN.md`, "The economy", in
the model (`models/uk/README.md`, "Interest rates", "Slumps that last", "Homelessness and
productivity"):

- **Interest rates.** Bank Rate is set each month by a rule (1.5 points for each point of
  inflation above 2%, a point for each point of unemployment below the natural rate, smoothed
  over six months, from 4.75%). The gilt yield moves half as much, a fifth of the debt pays
  Bank Rate, and the mortgage rate follows Bank Rate and the gilt yield over two and a half
  years. Households pay the change on their mortgages, by age and income, and their voters
  feel it. Firms pay it on their loans, and business investment reads the real cost of
  borrowing.
- **Slumps that last.** Firms and the state shed staff at 8% of the gap a month rather than a
  quarter. Long unemployment raises the natural rate and slows hiring for a time, and pay
  falls a quarter as fast as it rises.
- **The borrowing cliff.** Lenders refuse the gilts by a chance a month that rises with
  borrowing above the start (2% at a point, 10% at two, 22% at three), not at 1.2 points.
  The voters' curve is a smooth square: 0.1 of utility at a point, 0.4 at two.
- **Two bugs.** The 10-point tax rise never worsened the deficit by itself: the slump it
  causes opens "a bank in trouble", and the first answer (a rescue that doubles subsidies for
  six months) did. Without an answer the rise improves the balance every month (a test now
  says so). Pensioners' State Pensions are spread (log-normal, a quarter either way), so the
  basic rate at 30% moves pensioner poverty 3.7 points in its month, not 9. Since the State
  Pension now follows the benefits bill, a tenth off it moves pensioner poverty 4.7 points at
  once. That is a real effect, not bunching: each 1% moves it under a point.
- **The board.** Bank Rate, the mortgage rate and productivity are in Economy, homeless
  households in Housing.

`[params]` unchanged: `lender_premium_effect` 0.75, `vote_finances_effect` 1,
`vote_wear_effect` -0.025. The premium now also reaches mortgages: the crowd-pleaser's
mortgage rate is 4.10% in January 2027 against doing nothing's 3.72%. That is not too strong,
so the premium was left; the voters' curve was made a little steeper past a point instead (0.1
times the square, rather than 0.08, which matched S13.8's curve at one point). The method is
now a script, `python tools/uk/strategies.py` (the eight strategies, each bill made in its
month and again each month until it passes, every question its first answer, (b) its second;
`--months` gives each strategy every six months). On the S13.8 model it reproduced the S13.8
table to the seat, every figure, but two. The crowd-pleaser's crisis came a month earlier
(the script counts the month the question opens, not the month it is put). The wrecker's
capital earned was 151 rather than 152 (rounding of a sum).

### Strategies at a glance, after S14.5 (election in July 2029; the majority is 326)

The approval columns are Jan 2026 / Jan 2027 / Jun 2029. Seats in brackets are after S13.8.

| Strategy | Approval | CL seats (S13.8) | Government after | Balance Jun 2029 £bn/yr | Debt % GDP | Gilt yield | Unemployment | Bills passed | Capital earned / spent / wasted | Lenders refuse |
|---|---|---|---|---|---|---|---|---|---|---|
| (a) Nothing, first answers | 32.7 / 31.4 / 28.4% | 324 (325) | CL+SNP | -185 | 105.2 | 4.06% | 5.0% | 0 | 244 / 0 / 184 | no |
| (b) Nothing, second answers | 32.7 / 31.5 / 28.1% | 316 (315) | CL+SNP | -179 | 105.2 | 3.46% | 5.9% | 0 | 241 / 0 / 181 | no |
| (c) Crowd-pleaser | 33.7 / 30.8 / 27.7% | 305 (312) | CL+SNP+PC | -222 | 108.9 | 4.32% | 5.7% | 17 | 235 / 230 / 0 | Mar 2028 |
| (d) Austerity | 31.4 / 30.6 / 28.3% | 324 (314) | CL+SNP | -54 | 97.8 | 2.76% | 6.6% | 29 | 236 / 193 / 0 | no |
| (e) Reformer | 32.5 / 31.4 / 29.2% | 336 (336) | Centre-left | -180 | 103.7 | 4.04% | 4.8% | 8 | 247 / 163 / 24 | no |
| (f1) Basic rate 30% in Feb 2025 | 31.4 / 30.5 / 28.7% | 331 (309) | Centre-left | -126 | 101.0 | 3.21% | 5.3% | 1 | 235 / 17 / 158 | no |
| (f2) Health cut by a quarter in Feb 2025 | 28.6 / 27.5 / 26.6% | 279 (249) | CL+Lib+Grn+SNP+PC | -119 | 101.6 | 2.95% | 6.0% | 1 | 206 / 28 / 118 | no |
| (g) Wrecker | 26.2 / 25.8 / 16.8% | 68 (101) | Centre-right | +88 | 93.9 | 1.38% | 15.6% | 5 | 147 / 175 / 0 | no |
| (h) Tax early, please late | 31.3 / 31.9 / 31.4% | 373 (364) | Centre-left | -153 | 99.3 | 3.61% | 4.4% | 13 | 250 / 207 / 35 | no |

The largest move in one month, for any strategy, is 3.5 points of approval (the wrecker's
first bills) and 0.6 points of unemployment (the wrecker's education cut). It was 4.1 points of
unemployment before, when a cut to a service put its staff out of work in one month.

| Strategy, June 2029 | Bank Rate | Mortgage rate | Homeless households | Productivity |
|---|---|---|---|---|
| (a) Nothing, first answers | 3.88% | 3.68% | 132,000 | 99.98 |
| (c) Crowd-pleaser | 3.01% | 3.97% | 130,000 | 100.0 |
| (d) Austerity | 2.85% | 2.67% | 137,000 | 99.78 |
| (g) Wrecker | 0.11% | 1.55% | 186,000 | 99.32 |
| (h) Tax early, please late | 4.65% | 3.34% | 126,000 | 100.1 |

### The conclusions, a fourth time

**Against the targets of stage S14.5.**
- **Doing nothing** keeps 324 seats (316 with the second answers), inside 315 to 335.
- **Borrow and spend** (c) leads doing nothing by a point in January 2026. Then mortgages
  reprice upward (Bank Rate is 5.3% by January 2027), and by then it is behind. The
  crisis comes in March 2028 and it ends with 305 seats, 19 behind.
- **Austerity** (d) ties doing nothing at 324 seats. It borrows £131bn a year less, debt is
  7.4 points of output lower, and Bank Rate and mortgages are a point lower. It pays with a
  real slump: unemployment 6.2% in January 2027 and 6.6% at the election.
- **A paid-for programme** wins most: "tax early, please late" holds 373, the reformer 336.
- **The wrecker** loses office (68 seats; the centre-right governs alone).
- **No month jumps implausibly** (above).

**What changed and why.**
- Austerity gains 10 seats on S13.8 and the 30% basic rate 22. The Bank now cuts rates when
  policy tightens, and lower mortgage payments reach voters.
- Borrowing loses: the Bank raises rates against a borrowed boom, and the lenders' premium
  reaches mortgages.
- f2's quarter off health costs fewer seats (279 against 249). Its staff now go over a year,
  and Bank Rate falls to 1.5% in 2027.

**What is still wrong.**
- The wrecker's slump never heals: unemployment 15.6% and prices falling at the election, with
  Bank Rate at its floor. Halving health and cutting education by two fifths takes about 1.4
  million public jobs, and long unemployment then slows hiring to a quarter of its speed. The
  caps (three points of long unemployment at most) stop a spiral, but not a long slump. The
  wrecker is a test of losing office, so this was left. A milder policy slump (f2, austerity)
  heals in two to three years.
- A demand shock that ends overshoots after it: lower Bank Rate reaches mortgages over two and
  a half years, after the shock has gone. A year of business investment a quarter down leaves
  unemployment above its start two years on, but below doing nothing's from the 22nd month.
- Doing nothing ends with unemployment at 5.0% (4.8% after S13.8). Long unemployment builds
  from the 2025 drift above the natural rate.
- Productivity barely moves in a term (within 0.7 of 100 for every strategy). That is as the
  sources have it, so it is a slow statistic on the board.
- Austerity ties doing nothing rather than winning, as the target allows. Voters reward a fall
  in borrowing at about a seventh of the rate they punish a rise.

## After S15.2

Played a fifth time on 2026-11-16 with stage S15.2 of `docs/S15-PLAN.md` in the model: eleven new
groups (beliefs, work, places), four stances the belief groups react to, twelve new policies
(ten not in force), twelve new statistics, and the conditions the new groups feel
(`models/uk/politics/README.md`, "Beliefs, work and places"; `models/uk/POLICIES.md`, "Stage
S15.2"). The stances are centred: the electorate's mean reaction to any stance move is nil, so a
stance moves support between its two sides and hands out no votes of its own. `[params]`:
`vote_wear_effect` -0.025 to -0.022 (below); the rest unchanged. `python tools/uk/strategies.py`
as before, with two new strategies:

- **(i) A socialist programme:** a 1% wealth tax, every rail operator taken over, stronger unions
  and public pay 1 point a year above the plans (Feb 2025); corporation tax 28% (Jun 2025); 5% more
  for the NHS (Sep 2025); capped rent rises (Jan 2026); 30 hours of childcare for all (Jun 2026);
  £200 a year off energy bills (Jan 2027); 5% more for schools (Jun 2027).
- **(j) A law and order government:** tougher sentencing, a tenth more for police, courts and
  prisons, identity cards (Feb 2025); a £45,000 visa threshold (Jun 2025); minimum service levels
  in strikes (Sep 2025); a tenth more for defence (Jan 2026); tighter union law (Jun 2026); tough
  sentencing (Jan 2027); a fifth off aid (Jun 2027).

### Strategies at a glance, after S15.2 (election in July 2029; the majority is 326)

Approval columns are Jan 2026 / Jan 2027 / Jun 2029. Seats in brackets are after S14.5.

| Strategy | Approval | CL seats (S14.5) | Government after | Balance Jun 2029 £bn/yr | Debt % GDP | Unemployment | Bills passed | Lenders refuse |
|---|---|---|---|---|---|---|---|---|
| (a) Nothing, first answers | 32.7 / 31.5 / 28.5% | 325 (324) | CL+SNP | -184 | 105.2 | 5.0% | 0 | no |
| (b) Nothing, second answers | 32.8 / 31.5 / 28.1% | 315 (316) | CL+SNP | -179 | 105.2 | 5.9% | 0 | no |
| (c) Crowd-pleaser | 34.0 / 31.2 / 28.1% | 309 (305) | CL+SNP+PC | -223 | 108.9 | 5.7% | 17 | Mar 2028 |
| (d) Austerity | 31.2 / 30.5 / 28.4% | 327 (324) | Centre-left | -53 | 97.7 | 6.6% | 29 | no |
| (e) Reformer | 32.6 / 31.3 / 29.4% | 343 (336) | Centre-left | -180 | 103.7 | 4.8% | 8 | no |
| (f1) Basic rate 30% in Feb 2025 | 31.5 / 30.9 / 29.2% | 335 (331) | Centre-left | -125 | 100.8 | 5.3% | 1 | no |
| (f2) Health cut by a quarter in Feb 2025 | 28.0 / 27.2 / 26.6% | 284 (279) | CL+Lib+Grn+SNP+PC | -117 | 101.3 | 5.9% | 1 | no |
| (g) Wrecker | 25.5 / 26.3 / 16.6% | 64 (68) | CR+PopR | +95 | 94.4 | 14.9% | 5 | no |
| (h) Tax early, please late | 31.2 / 31.9 / 31.8% | 372 (373) | Centre-left | -152 | 99.1 | 4.4% | 13 | no |
| (i) A socialist programme | 33.7 / 32.9 / 30.4% | 349 (new) | Centre-left | -197 | 103.7 | 4.9% | 10 | no |
| (j) A law and order government | 33.6 / 32.4 / 29.6% | 349 (new) | Centre-left | -184 | 105.2 | 4.9% | 9 | no |

The largest one-month move is 3.3 points of approval (the wrecker's first bills) and 0.6 of
unemployment. With the stances off (`--param belief_effect=0`) the socialist programme holds 354
and law and order 336: the stances are worth -5 and +13 seats.

### The new groups, June 2029 (approval; change against doing nothing)

| Strategy | Socialists | Capitalists | Liberals | Conservatives | Environmentalists | Patriots | Public sector | Trade unionists | Farmers | Town | Countryside |
|---|---|---|---|---|---|---|---|---|---|---|---|
| (a) Nothing | 30.1 | 28.0 | 31.7 | 26.0 | 31.0 | 26.1 | 33.3 | 32.5 | 25.8 | 29.5 | 24.4 |
| (c) Crowd-pleaser | +0.5 | -1.5 | -0.2 | -0.5 | -0.3 | -0.7 | -1.1 | -1.4 | -1.1 | -0.3 | -1.0 |
| (d) Austerity | -0.7 | +0.5 | -0.7 | +0.3 | -0.6 | +0.5 | -0.4 | -0.1 | +0.6 | -0.3 | +0.7 |
| (e) Reformer | +1.6 | -0.1 | +0.5 | +1.3 | +0.4 | +1.1 | -0.5 | -0.7 | +0.3 | +1.0 | +0.6 |
| (h) Tax early, please late | +4.3 | +2.3 | +3.6 | +3.2 | +3.5 | +3.0 | +2.5 | +2.1 | +2.4 | +3.5 | +2.4 |
| (i) Socialist programme | +2.7 | +1.2 | +2.3 | +1.6 | +2.2 | +1.5 | +2.5 | +2.3 | +1.6 | +2.1 | +1.2 |
| (j) Law and order | +0.6 | +0.9 | -1.1 | +2.7 | -0.8 | +2.8 | -1.2 | -0.6 | +1.9 | +0.8 | +2.5 |

### The conclusions, a fifth time

- **Doing nothing** keeps 325 seats with the first answers, inside 320 to 332; the second
  answers give 315. Rents, energy bills and the slow squeeze on public pay now cost a little by
  2029, so the scenario's wear of office was eased from -0.025 to -0.022 a year to keep (a) in
  its band.
- **Governing sensibly pays.** The reformer (343) and austerity (327) are at or above doing
  nothing; the crowd-pleaser (309) is behind it; the wrecker is out of office.
- **Two programmes, one result.** The socialist programme and law and order both hold 349. They
  differ by what they do: the socialist one raises public pay and cuts energy bills and rents, so
  every group gains (public sector workers +2.5, unions +2.3), and borrows £13bn a year more; law
  and order costs the liberals, environmentalists and public sector workers while conservatives,
  patriots and the countryside gain 2.5 to 2.8.
- **Belief groups move less than asked.** Centred and capped so no programme wins more than about
  15 seats from stances, a single clear move shifts its two groups by about 1.3 points each way
  (conservatives against liberals) and a whole programme by 2 to 4 points relative to its
  opponents. Under the socialist programme the capitalists still gain (+1.2), because its pay
  and bills lift every group by more than the state stance takes from them. Larger stance
  effects split the groups more but bring back a dominant law and order strategy (380 seats at
  0.35 and a saturation of three); this is the trade-off the size settles.
- **"Tax early, please late"** holds 372, 29 above the reformer. Its lead does not come from the
  stances (375 with them off): it is the S13 finding that a tax rise paid early and spent late
  wins. The stances could not narrow it honestly, and no other change was made for it.
- **Still wrong:** groups move by who is in which voter types, not by members alone, so small
  groups (farmers) and overlapping ones (unions with capitalists) move with their neighbours.

## Month by month, by strategy

Groups: the lowest and highest group approval in that month. Capital: held at the end of the month; earned, spent and wasted at the cap over the 12 months to that month. Growth is the annual rate of output growth that month.

### (a) Do nothing, first answers

| Month | Approval | Groups (lowest / highest) | Capital held | Earned / spent / wasted (12 months to here) | Balance £bn/yr | Debt % GDP | Growth | Unempl. | Inflation | Situations in force |
|---|---|---|---|---|---|---|---|---|---|---|
| Jan 2025 | 33.9% | pensioners 21% / young 49% | 45 | 5 / 0 / 0 | -149 | 97.4 | +0.0% | 4.3% | 2.1% | none |
| Jul 2025 | 33.5% | pensioners 21% / young 48% | 76 | 36 / 0 / 0 | -162 | 97.7 | +4.0% | 4.6% | 1.9% | strong growth |
| Jan 2026 | 33.2% | pensioners 21% / young 48% | 95 | 50 / 0 / 0 | -165 | 98.6 | +1.8% | 4.5% | 2.0% | emissions above path |
| Jan 2027 | 32.3% | pensioners 20% / young 47% | 100 | 35 / 0 / 30 | -173 | 100.3 | +1.7% | 4.4% | 2.0% | debt>GDP, emissions above path |
| Jan 2028 | 31.2% | pensioners 19% / young 46% | 100 | 32 / 0 / 32 | -179 | 102.5 | +1.3% | 4.5% | 2.0% | debt>GDP, emissions above path |
| Jan 2029 | 30.5% | pensioners 19% / young 45% | 100 | 29 / 0 / 29 | -185 | 104.6 | +1.2% | 4.7% | 1.9% | debt>GDP, emissions above path, record waiting list |
| Jun 2029 | 29.8% | pensioners 18% / young 44% | 100 | 28 / 0 / 28 | -189 | 105.4 | +1.5% | 4.8% | 1.8% | debt>GDP, health strain, emissions above path, record waiting list |
| Jul 2029 | 29.7% | pensioners 18% / young 44% | 100 | 28 / 0 / 28 | -193 | 105.5 | +1.8% | 4.8% | 1.8% | debt>GDP, health strain, emissions above path, record waiting list |
| Dec 2029 | 31.2% | pensioners 19% / young 46% | 100 | 39 / 0 / 39 | -196 | 106.2 | +1.7% | 4.7% | 1.9% | debt>GDP, health strain, emissions above path, record waiting list |

Election, July 2029: CL 344, CR 180, Lib 72, PopR 6, Grn 4, SNP 10, PC 4, NI 18, Oth 12; government after it: CL. Bills passed 0 (0.0 a year), refused 0; capital spent 0, wasted at the cap 128.

Change January 2025 to June 2029: approval -4.05 pts; groups from london -5.35 to pensioners -2.99.

### (b) Do nothing, second answers

| Month | Approval | Groups (lowest / highest) | Capital held | Earned / spent / wasted (12 months to here) | Balance £bn/yr | Debt % GDP | Growth | Unempl. | Inflation | Situations in force |
|---|---|---|---|---|---|---|---|---|---|---|
| Jan 2025 | 33.9% | pensioners 21% / young 49% | 45 | 5 / 0 / 0 | -149 | 97.4 | +0.0% | 4.3% | 2.1% | none |
| Jul 2025 | 33.5% | pensioners 21% / young 48% | 76 | 36 / 0 / 0 | -158 | 98.1 | +2.6% | 4.6% | 1.9% | none |
| Jan 2026 | 33.2% | pensioners 21% / young 48% | 95 | 50 / 0 / 0 | -164 | 98.8 | +2.1% | 4.6% | 1.9% | none |
| Jan 2027 | 32.3% | pensioners 20% / young 46% | 100 | 35 / 0 / 30 | -167 | 100.8 | +1.1% | 4.6% | 1.9% | debt>GDP, emissions above path, record waiting list |
| Jan 2028 | 30.9% | pensioners 19% / young 45% | 100 | 29 / 0 / 29 | -176 | 102.6 | +0.9% | 5.4% | 1.5% | debt>GDP, emissions above path |
| Jan 2029 | 30.2% | pensioners 19% / young 44% | 100 | 29 / 0 / 29 | -187 | 104.7 | +1.8% | 5.1% | 1.7% | debt>GDP, emissions above path, record waiting list |
| Jun 2029 | 29.8% | pensioners 19% / young 44% | 100 | 28 / 0 / 28 | -191 | 105.5 | +1.8% | 4.9% | 1.8% | debt>GDP, health strain, emissions above path, record waiting list |
| Jul 2029 | 29.8% | pensioners 19% / young 44% | 100 | 27 / 0 / 27 | -191 | 105.6 | +1.8% | 4.8% | 1.8% | debt>GDP, health strain, emissions above path, record waiting list |
| Dec 2029 | 31.5% | pensioners 20% / young 46% | 100 | 39 / 0 / 39 | -194 | 106.4 | +1.7% | 4.7% | 1.9% | debt>GDP, health strain, emissions above path, record waiting list |

Election, July 2029: CL 344, CR 180, Lib 72, PopR 6, Grn 4, SNP 10, PC 4, NI 18, Oth 12; government after it: CL. Bills passed 0 (0.0 a year), refused 0; capital spent 0, wasted at the cap 124.

Against doing nothing in June 2029: approval +0.04 pts; groups from young -0.49 to pensioners +0.43 (spread 0.92 pts).

### (c) Crowd-pleaser

| Month | Approval | Groups (lowest / highest) | Capital held | Earned / spent / wasted (12 months to here) | Balance £bn/yr | Debt % GDP | Growth | Unempl. | Inflation | Situations in force |
|---|---|---|---|---|---|---|---|---|---|---|
| Jan 2025 | 33.9% | pensioners 21% / young 49% | 45 | 5 / 0 / 0 | -149 | 97.4 | +0.0% | 4.3% | 2.1% | none |
| Jul 2025 | 34.7% | pensioners 22% / young 50% | 8 | 38 / 69 / 0 | -184 | 96.9 | +4.9% | 3.9% | 2.1% | strong growth |
| Jan 2026 | 34.7% | pensioners 22% / young 50% | 23 | 53 / 75 / 0 | -190 | 97.9 | +1.8% | 3.8% | 2.0% | emissions above path |
| Jan 2027 | 33.9% | pensioners 21% / young 50% | 37 | 40 / 27 / 0 | -199 | 100.1 | +1.5% | 3.8% | 2.2% | debt>GDP, emissions above path, waiting list falling |
| Jan 2028 | 32.9% | pensioners 20% / young 48% | 4 | 37 / 70 / 0 | -212 | 103.0 | +1.7% | 4.5% | 1.9% | debt>GDP, emissions above path, waiting list falling |
| Jan 2029 | 32.6% | pensioners 20% / young 47% | 7 | 35 / 32 / 0 | -223 | 105.9 | +1.4% | 4.7% | 1.8% | debt>GDP, emissions above path |
| Jun 2029 | 32.1% | pensioners 20% / young 47% | 4 | 34 / 35 / 0 | -235 | 106.8 | +2.3% | 4.7% | 1.8% | debt>GDP, emissions above path |
| Jul 2029 | 32.0% | pensioners 20% / young 47% | 7 | 34 / 35 / 0 | -235 | 107.0 | +2.2% | 4.7% | 1.8% | debt>GDP, emissions above path |
| Dec 2029 | 33.6% | pensioners 21% / young 49% | 9 | 46 / 41 / 0 | -263 | 107.4 | +3.2% | 4.0% | 2.0% | strong growth, debt>GDP, emissions above path |

Election, July 2029: CL 377, CR 151, Lib 72, PopR 5, Grn 4, SNP 10, PC 4, NI 18, Oth 9; government after it: CL. Bills passed 21 (4.2 a year), refused 0; capital spent 244, wasted at the cap 0.

Bills: Feb 2025 basic_rate 0.19 (5.6); Feb 2025 spending_health 2.23e+10 (5.9); Feb 2025 ev_grant 3000 (20.0); Feb 2025 personal_allowance 1.307e+04 (5.6); Feb 2025 benefits_bill 2.234e+10 (5.9); Jun 2025 insulation_programme 2e+08 (20.0); Jul 2025 vat_rate 0.19 (6.2); Aug 2025 spending_education 1.122e+10 (5.9); Apr 2026 social_housing 3e+08 (26.6); Feb 2027 winter_fuel_payment 2 (35.0); Jan 2028 free_school_meals 2 (35.0); Jun 2028 prescription_charge 0 (13.9); Sep 2028 bus_fare_cap 1 (9.5); Dec 2028 fuel_duty 47.95 (8.6); Feb 2029 child_benefit_eldest 1431 (5.6); Apr 2029 spending_social_care 4.686e+09 (5.9); Jun 2029 basic_rate 0.18 (5.6); Aug 2029 spending_health 2.297e+10 (5.9); Sep 2029 personal_allowance 1.357e+04 (5.6); Nov 2029 benefits_bill 2.301e+10 (5.9); Dec 2029 vat_rate 0.18 (6.2)

Against doing nothing in June 2029: approval +2.35 pts; groups from pensioners +1.67 to low_income +3.50 (spread 1.83 pts).

### (d) Austerity

| Month | Approval | Groups (lowest / highest) | Capital held | Earned / spent / wasted (12 months to here) | Balance £bn/yr | Debt % GDP | Growth | Unempl. | Inflation | Situations in force |
|---|---|---|---|---|---|---|---|---|---|---|
| Jan 2025 | 33.9% | pensioners 21% / young 49% | 45 | 5 / 0 / 0 | -149 | 97.4 | +0.0% | 4.3% | 2.1% | none |
| Jul 2025 | 32.2% | pensioners 20% / young 47% | 9 | 35 / 66 / 0 | -122 | 98.9 | +1.1% | 5.5% | 1.8% | none |
| Jan 2026 | 30.9% | pensioners 19% / young 46% | 6 | 45 / 85 / 0 | -126 | 100.7 | +0.1% | 6.2% | 1.9% | recession, high unempl., debt>GDP, record waiting list |
| Jan 2027 | 30.2% | pensioners 18% / young 44% | 5 | 29 / 30 / 0 | -114 | 101.2 | +1.6% | 5.7% | 1.7% | high unempl., debt>GDP, health strain, emissions above path, record waiting list |
| Jan 2028 | 29.1% | pensioners 18% / young 43% | 3 | 23 / 24 / 0 | -102 | 101.3 | +1.2% | 5.7% | 1.7% | debt>GDP, health strain, emissions above path, record waiting list |
| Jan 2029 | 28.5% | pensioners 17% / young 43% | 4 | 24 / 23 / 0 | -94 | 101.8 | +1.4% | 5.8% | 1.7% | debt>GDP, health strain, emissions above path, record waiting list |
| Jun 2029 | 28.5% | pensioners 18% / young 42% | 7 | 23 / 24 / 0 | -93 | 101.6 | +1.9% | 5.5% | 1.7% | debt>GDP, health strain, emissions above path, record waiting list |
| Jul 2029 | 28.4% | pensioners 18% / young 42% | 3 | 23 / 24 / 0 | -92 | 101.6 | +1.5% | 5.5% | 1.6% | debt>GDP, health strain, emissions above path, record waiting list |
| Dec 2029 | 30.8% | pensioners 19% / young 45% | 7 | 36 / 30 / 0 | -84 | 101.6 | +1.2% | 5.3% | 1.7% | debt>GDP, health strain, emissions above path, record waiting list |

Election, July 2029: CL 326, CR 192, Lib 72, PopR 6, Grn 4, SNP 15, PC 4, NI 18, Oth 13; government after it: CL. Bills passed 32 (6.4 a year), refused 0; capital spent 192, wasted at the cap 0.

Bills: Feb 2025 basic_rate 0.21 (5.6); Feb 2025 spending_general 2.136e+09 (6.5); Feb 2025 vat_rate 0.21 (6.2); Feb 2025 benefits_bill 2.104e+10 (5.9); Feb 2025 public_investment_bill 1.126e+10 (6.0); Feb 2025 spending_health 2.122e+10 (5.6); Feb 2025 subsidies_bill 2.964e+09 (6.0); Mar 2025 transfers_abroad_bill 2.787e+09 (7.0); Apr 2025 spending_education 1.068e+10 (5.6); Jun 2025 corporation_tax_rate 0.26 (6.2); Jul 2025 basic_rate 0.22 (5.6); Aug 2025 spending_general 2.029e+09 (6.4); Oct 2025 vat_rate 0.22 (6.2); Dec 2025 benefits_bill 2.041e+10 (5.9); Mar 2026 public_investment_bill 1.069e+10 (6.0); May 2026 spending_health 2.08e+10 (5.6); Jul 2026 subsidies_bill 2.816e+09 (6.0); Oct 2026 transfers_abroad_bill 2.508e+09 (6.8); Dec 2026 spending_education 1.046e+10 (5.6); Mar 2027 corporation_tax_rate 0.27 (6.2); Jun 2027 basic_rate 0.23 (5.6); Oct 2027 spending_general 1.928e+09 (6.4); Jan 2028 vat_rate 0.23 (6.2); Apr 2028 benefits_bill 1.979e+10 (5.8); Jul 2028 public_investment_bill 1.016e+10 (5.9); Sep 2028 spending_health 2.038e+10 (5.6); Dec 2028 subsidies_bill 2.675e+09 (5.9); Apr 2029 transfers_abroad_bill 2.258e+09 (6.6); Jul 2029 spending_education 1.025e+10 (5.6); Sep 2029 corporation_tax_rate 0.28 (6.2); Oct 2029 basic_rate 0.24 (5.6); Dec 2029 spending_general 1.831e+09 (6.3)

Against doing nothing in June 2029: approval -1.31 pts; groups from young -1.80 to pensioners -0.49 (spread 1.31 pts).

### (e) Reformer

| Month | Approval | Groups (lowest / highest) | Capital held | Earned / spent / wasted (12 months to here) | Balance £bn/yr | Debt % GDP | Growth | Unempl. | Inflation | Situations in force |
|---|---|---|---|---|---|---|---|---|---|---|
| Jan 2025 | 33.9% | pensioners 21% / young 49% | 45 | 5 / 0 / 0 | -149 | 97.4 | +0.0% | 4.3% | 2.1% | none |
| Jul 2025 | 33.4% | pensioners 21% / young 48% | 12 | 36 / 64 / 0 | -161 | 97.6 | +4.2% | 4.6% | 1.9% | strong growth |
| Jan 2026 | 32.9% | pensioners 21% / young 47% | 10 | 49 / 84 / 0 | -159 | 98.3 | +2.1% | 4.4% | 2.2% | emissions above path |
| Jan 2027 | 31.6% | pensioners 20% / young 47% | 10 | 32 / 32 / 0 | -163 | 99.5 | +1.8% | 4.3% | 2.2% | emissions above path |
| Jan 2028 | 30.8% | pensioners 19% / young 46% | 21 | 31 / 20 / 0 | -173 | 101.1 | +1.7% | 4.4% | 2.1% | debt>GDP, emissions above path |
| Jan 2029 | 30.5% | pensioners 19% / young 45% | 23 | 29 / 27 / 0 | -180 | 102.8 | +1.5% | 4.5% | 2.0% | debt>GDP, emissions above path, record waiting list |
| Jun 2029 | 29.8% | pensioners 18% / young 45% | 34 | 28 / 0 / 0 | -182 | 103.6 | +1.4% | 4.7% | 1.9% | debt>GDP, health strain, emissions above path, record waiting list |
| Jul 2029 | 29.7% | pensioners 18% / young 45% | 37 | 28 / 0 / 0 | -182 | 103.7 | +1.4% | 4.7% | 1.9% | debt>GDP, health strain, emissions above path, record waiting list |
| Dec 2029 | 31.1% | pensioners 19% / young 47% | 24 | 39 / 35 / 0 | -189 | 104.4 | +1.6% | 4.7% | 1.9% | debt>GDP, health strain, emissions above path, record waiting list |

Election, July 2029: CL 344, CR 180, Lib 72, PopR 6, Grn 4, SNP 10, PC 4, NI 18, Oth 12; government after it: CL. Bills passed 9 (1.8 a year), refused 0; capital spent 198, wasted at the cap 0.

Bills: Feb 2025 planning_rules 4 (35.0); Jun 2025 sentencing 4 (29.0); Aug 2025 alcohol_duty 1.25 (11.0); Nov 2025 tobacco_duty 1.25 (9.0); Mar 2026 fuel_duty 62.95 (12.2); Nov 2026 ev_grant 3000 (20.0); Jun 2027 insulation_programme 2e+08 (20.0); May 2028 social_housing 3e+08 (26.6); Aug 2029 rent_controls 1 (35.0)

Against doing nothing in June 2029: approval -0.01 pts; groups from midlife -0.33 to low_income +1.04 (spread 1.37 pts).

### (f1) Basic rate to 30% in February 2025, then nothing

| Month | Approval | Groups (lowest / highest) | Capital held | Earned / spent / wasted (12 months to here) | Balance £bn/yr | Debt % GDP | Growth | Unempl. | Inflation | Situations in force |
|---|---|---|---|---|---|---|---|---|---|---|
| Jan 2025 | 33.9% | pensioners 21% / young 49% | 45 | 5 / 0 / 0 | -149 | 97.4 | +0.0% | 4.3% | 2.1% | none |
| Jul 2025 | 31.1% | pensioners 20% / young 45% | 62 | 33 / 11 / 0 | -170 | 99.5 | +2.4% | 5.9% | 1.4% | none |
| Jan 2026 | 31.3% | pensioners 20% / young 45% | 77 | 43 / 11 / 0 | -142 | 100.7 | +2.0% | 5.8% | 1.4% | debt>GDP |
| Jan 2027 | 31.3% | pensioners 20% / young 46% | 100 | 31 / 0 / 8 | -148 | 101.8 | +2.1% | 4.8% | 1.8% | debt>GDP, emissions above path |
| Jan 2028 | 31.1% | pensioners 19% / young 46% | 100 | 31 / 0 / 31 | -150 | 103.1 | +1.3% | 4.5% | 2.0% | debt>GDP, emissions above path |
| Jan 2029 | 30.5% | pensioners 19% / young 45% | 100 | 29 / 0 / 29 | -153 | 104.4 | +1.1% | 4.7% | 1.9% | debt>GDP, emissions above path, record waiting list |
| Jun 2029 | 29.8% | pensioners 18% / young 44% | 100 | 28 / 0 / 28 | -157 | 105.0 | +1.4% | 4.8% | 1.8% | debt>GDP, health strain, emissions above path, record waiting list |
| Jul 2029 | 29.8% | pensioners 18% / young 44% | 100 | 28 / 0 / 28 | -161 | 105.0 | +1.8% | 4.8% | 1.8% | debt>GDP, health strain, emissions above path, record waiting list |
| Dec 2029 | 31.2% | pensioners 19% / young 46% | 100 | 39 / 0 / 39 | -163 | 105.4 | +1.7% | 4.7% | 1.9% | debt>GDP, health strain, emissions above path, record waiting list |

Election, July 2029: CL 344, CR 180, Lib 72, PopR 6, Grn 4, SNP 10, PC 4, NI 18, Oth 12; government after it: CL. Bills passed 1 (0.2 a year), refused 0; capital spent 11, wasted at the cap 105.

Against doing nothing in June 2029: approval +0.05 pts; groups from pensioners +0.02 to young +0.13 (spread 0.11 pts).

### (f2) Health spending cut by a quarter in February 2025, then nothing

| Month | Approval | Groups (lowest / highest) | Capital held | Earned / spent / wasted (12 months to here) | Balance £bn/yr | Debt % GDP | Growth | Unempl. | Inflation | Situations in force |
|---|---|---|---|---|---|---|---|---|---|---|
| Jan 2025 | 33.9% | pensioners 21% / young 49% | 45 | 5 / 0 / 0 | -149 | 97.4 | +0.0% | 4.3% | 2.1% | none |
| Jul 2025 | 29.4% | pensioners 18% / young 44% | 59 | 32 / 12 / 0 | -177 | 100.9 | +2.1% | 7.6% | 1.0% | high unempl., debt>GDP, health strain, record waiting list |
| Jan 2026 | 28.5% | pensioners 17% / young 43% | 71 | 38 / 12 / 0 | -150 | 101.9 | +2.4% | 6.7% | 1.2% | high unempl., debt>GDP, health strain, record waiting list |
| Jan 2027 | 28.1% | pensioners 16% / young 43% | 93 | 22 / 0 / 0 | -153 | 103.0 | +2.3% | 4.8% | 1.8% | debt>GDP, health strain, emissions above path, record waiting list |
| Jan 2028 | 27.9% | pensioners 16% / young 43% | 100 | 21 / 0 / 14 | -155 | 104.4 | +1.7% | 4.5% | 2.0% | debt>GDP, health strain, emissions above path, record waiting list |
| Jan 2029 | 27.3% | pensioners 16% / young 42% | 100 | 20 / 0 / 20 | -159 | 105.8 | +1.5% | 4.7% | 1.9% | debt>GDP, health strain, emissions above path, record waiting list |
| Jun 2029 | 26.7% | pensioners 15% / young 42% | 100 | 19 / 0 / 19 | -159 | 106.4 | +1.3% | 4.7% | 1.9% | debt>GDP, health strain, emissions above path, record waiting list |
| Jul 2029 | 26.7% | pensioners 15% / young 42% | 100 | 18 / 0 / 18 | -160 | 106.5 | +1.4% | 4.8% | 1.8% | debt>GDP, health strain, emissions above path, record waiting list |
| Dec 2029 | 55.8% | pensioners 39% / scotland 79% | 100 | 51 / 0 / 51 | -165 | 106.9 | +1.8% | 4.8% | 1.9% | debt>GDP, health strain, emissions above path, record waiting list |

Election, July 2029: CL 284, CR 224, Lib 73, PopR 7, Grn 4, SNP 22, PC 4, NI 18, Oth 14; government after it: CL+Lib+Grn+SNP+PC. Bills passed 1 (0.2 a year), refused 0; capital spent 12, wasted at the cap 83.

Against doing nothing in June 2029: approval -3.08 pts; groups from north -3.64 to young -2.49 (spread 1.15 pts).

### (g) Wrecker (extra): every unpopular big move the capital allows

| Month | Approval | Groups (lowest / highest) | Capital held | Earned / spent / wasted (12 months to here) | Balance £bn/yr | Debt % GDP | Growth | Unempl. | Inflation | Situations in force |
|---|---|---|---|---|---|---|---|---|---|---|
| Jan 2025 | 33.9% | pensioners 21% / young 49% | 45 | 5 / 0 / 0 | -149 | 97.4 | +0.0% | 4.3% | 2.1% | none |
| Jul 2025 | 20.0% | pensioners 12% / young 33% | 13 | 24 / 51 / 0 | -32 | 109.0 | -8.6% | 13.8% | 2.8% | recession, high unempl., debt>GDP, health strain, net zero on track, record waiting list |
| Jan 2026 | 18.4% | pensioners 10% / young 31% | 5 | 25 / 65 / 0 | -12 | 109.9 | +5.7% | 15.9% | 1.9% | strong growth, high unempl., debt>GDP, health strain, net zero on track, record waiting list |
| Jan 2027 | 21.9% | pensioners 12% / young 36% | 17 | 12 / 0 / 0 | +3 | 105.9 | +3.3% | 8.1% | 1.8% | strong growth, high unempl., debt>GDP, surplus, health strain, net zero on track, record waiting list |
| Jan 2028 | 20.3% | pensioners 12% / young 34% | 12 | 12 / 17 / 0 | +31 | 104.3 | +1.7% | 7.7% | 1.3% | high unempl., debt>GDP, surplus, health strain, schools strain, net zero on track, record waiting list |
| Jan 2029 | 21.2% | pensioners 12% / young 35% | 24 | 12 / 0 / 0 | +42 | 99.6 | +1.9% | 5.3% | 1.7% | debt>GDP, surplus, health strain, schools strain, record waiting list |
| Jun 2029 | 21.4% | pensioners 12% / young 36% | 29 | 12 / 0 / 0 | +47 | 97.6 | +1.7% | 4.9% | 1.9% | surplus, health strain, schools strain, record waiting list |
| Jul 2029 | 21.4% | pensioners 12% / young 36% | 30 | 12 / 0 / 0 | +48 | 97.2 | +1.6% | 4.8% | 1.9% | surplus, health strain, schools strain, record waiting list |
| Dec 2029 | 39.7% | young 18% / pensioners 57% | 64 | 41 / 0 / 0 | +52 | 95.1 | +1.4% | 4.7% | 1.9% | surplus, health strain, schools strain, record waiting list |

Election, July 2029: CL 156, CR 283, Lib 75, PopR 41, Grn 7, SNP 43, PC 7, NI 18, Oth 20; government after it: CR+PopR+NI. Bills passed 5 (1.0 a year), refused 0; capital spent 82, wasted at the cap 0.

Bills: Feb 2025 spending_health 1.083e+10 (20.0); Feb 2025 basic_rate 0.35 (14.0); Apr 2025 vat_rate 0.3 (17.0); Sep 2025 benefits_bill 1.518e+10 (14.0); Feb 2027 spending_education 6.537e+09 (17.0)

Against doing nothing in June 2029: approval -8.36 pts; groups from north -9.94 to pensioners -5.68 (spread 4.26 pts).

### (h) Tax early, please late (extra): basic rate 25% and VAT 23% in February 2025; from January 2027 the popular policies with lasting reactions

| Month | Approval | Groups (lowest / highest) | Capital held | Earned / spent / wasted (12 months to here) | Balance £bn/yr | Debt % GDP | Growth | Unempl. | Inflation | Situations in force |
|---|---|---|---|---|---|---|---|---|---|---|
| Jan 2025 | 33.9% | pensioners 21% / young 49% | 45 | 5 / 0 / 0 | -149 | 97.4 | +0.0% | 4.3% | 2.1% | none |
| Jul 2025 | 31.4% | pensioners 20% / young 46% | 57 | 33 / 17 / 0 | -123 | 98.2 | +3.2% | 5.5% | 2.5% | strong growth |
| Jan 2026 | 31.6% | pensioners 20% / young 46% | 72 | 44 / 17 / 0 | -131 | 98.6 | +2.0% | 5.5% | 2.2% | none |
| Jan 2027 | 32.4% | pensioners 20% / young 47% | 14 | 32 / 89 / 2 | -143 | 99.2 | +2.4% | 4.7% | 2.1% | emissions above path |
| Jan 2028 | 32.5% | pensioners 20% / young 48% | 6 | 34 / 42 / 0 | -151 | 100.0 | +2.3% | 4.1% | 2.3% | debt>GDP, emissions above path |
| Jan 2029 | 32.3% | pensioners 20% / young 47% | 5 | 34 / 35 / 0 | -158 | 101.0 | +1.7% | 4.4% | 2.1% | debt>GDP, emissions above path |
| Jun 2029 | 32.1% | pensioners 20% / young 47% | 7 | 34 / 47 / 0 | -166 | 101.0 | +2.7% | 3.9% | 2.3% | strong growth, debt>GDP, emissions above path |
| Jul 2029 | 32.2% | pensioners 20% / young 47% | 4 | 34 / 53 / 0 | -172 | 100.7 | +3.6% | 3.7% | 2.4% | strong growth, debt>GDP, emissions above path |
| Dec 2029 | 33.5% | pensioners 21% / young 49% | 5 | 45 / 77 / 0 | -198 | 99.8 | +5.3% | 3.4% | 2.6% | strong growth, debt>GDP, emissions above path |

Election, July 2029: CL 383, CR 146, Lib 72, PopR 5, Grn 4, SNP 9, PC 4, NI 18, Oth 9; government after it: CL. Bills passed 17 (3.4 a year), refused 0; capital spent 225, wasted at the cap 2.

Bills: Feb 2025 basic_rate 0.25 (8.0); Feb 2025 vat_rate 0.23 (8.6); Jan 2027 ev_grant 3000 (20.0); Jan 2027 insulation_programme 2e+08 (20.0); Jan 2027 winter_fuel_payment 2 (35.0); Jan 2027 prescription_charge 0 (13.9); Jul 2027 social_housing 3e+08 (26.6); Oct 2027 bus_fare_cap 1 (9.5); Dec 2027 spending_health 2.23e+10 (5.9); Jan 2029 free_school_meals 2 (35.0); Mar 2029 spending_health 2.297e+10 (5.9); May 2029 spending_health 2.366e+10 (6.0); Jul 2029 spending_health 2.437e+10 (6.0); Sep 2029 spending_health 2.51e+10 (6.0); Oct 2029 spending_health 2.586e+10 (6.0); Nov 2029 spending_health 2.663e+10 (6.1); Dec 2029 spending_health 2.743e+10 (6.1)

Against doing nothing in June 2029: approval +2.35 pts; groups from pensioners +1.81 to low_income +3.66 (spread 1.85 pts).

### Pacing

(a) Do nothing, first answers: 2025: 2 questions, 2 situation starts/ends, 0 months approval moved 0.5+ pts; 2026: 4 questions, 2 situation starts/ends, 0 months approval moved 0.5+ pts; 2027: 4 questions, 2 situation starts/ends, 0 months approval moved 0.5+ pts; 2028: 1 questions, 1 situation starts/ends, 0 months approval moved 0.5+ pts; 2029: 2 questions, 1 situation starts/ends, 1 months approval moved 0.5+ pts. Longest stretch with no question and no situation change: 9 months, to Apr 2029.

Questions: pay_claim Jul 2025, steelworks Dec 2025, defence_summit Jun 2026, prisons_full Jun 2026, net_zero_warning Jul 2026, investor Aug 2026, energy_shock Mar 2027, nhs_winter Jul 2027, floods Sep 2027, prisons_full Dec 2027, nhs_winter Jul 2028, prisons_full Jun 2029, nhs_winter Jul 2029

(c) Crowd-pleaser: 2025: 2 questions, 5 situation starts/ends, 1 months approval moved 0.5+ pts; 2026: 4 questions, 1 situation starts/ends, 0 months approval moved 0.5+ pts; 2027: 3 questions, 1 situation starts/ends, 0 months approval moved 0.5+ pts; 2028: 0 questions, 1 situation starts/ends, 0 months approval moved 0.5+ pts; 2029: 2 questions, 3 situation starts/ends, 1 months approval moved 0.5+ pts. Longest stretch with no question and no situation change: 12 months, to May 2029.

Questions: pay_claim Jul 2025, steelworks Dec 2025, defence_summit Jun 2026, prisons_full Jun 2026, net_zero_warning Jul 2026, investor Aug 2026, energy_shock Mar 2027, floods Sep 2027, prisons_full Dec 2027, prisons_full Jun 2029, nhs_winter Nov 2029

(d) Austerity: 2025: 4 questions, 6 situation starts/ends, 2 months approval moved 0.5+ pts; 2026: 4 questions, 3 situation starts/ends, 0 months approval moved 0.5+ pts; 2027: 5 questions, 3 situation starts/ends, 2 months approval moved 0.5+ pts; 2028: 1 questions, 0 situation starts/ends, 0 months approval moved 0.5+ pts; 2029: 2 questions, 0 situation starts/ends, 2 months approval moved 0.5+ pts. Longest stretch with no question and no situation change: 9 months, to Sep 2028.

Questions: pay_claim Jul 2025, bank_rescue Aug 2025, nhs_winter Oct 2025, steelworks Dec 2025, defence_summit Jun 2026, prisons_full Jun 2026, investor Aug 2026, nhs_winter Oct 2026, net_zero_warning Jan 2027, energy_shock Mar 2027, floods Sep 2027, nhs_winter Oct 2027, prisons_full Dec 2027, nhs_winter Oct 2028, prisons_full Jun 2029, nhs_winter Oct 2029

