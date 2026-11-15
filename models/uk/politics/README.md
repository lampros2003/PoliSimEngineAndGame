# The UK's voters

`politics.toml` and the files here are written by `tools/uk/voters.py` (run by
`tools/uk/calibrate.py`); do not edit them. Stage S5.2 of `docs/S5-PLAN.md`.

## Who votes

The adults of the synthetic households (`../households/`) aged 18 and over, counted by
their households' weights, in 600 voter types: region (12) by age band (18 to 24, 25 to
34, 35 to 49, 50 to 64, 65 and over) by household income quintile (from the household's
base-year decile) by in work or not (`voter_types.csv`). Since the households are raked to
the population and employment each month, the voter types age and move with them.

## How they choose

Nine blocs, or not voting. For voter type `t` and option `o`:

```
utility = intercept[region of t, o] + age effect[age band of t, o]
          + for the blocs in government:
              2.5 * (t's change in real household income)
              - 6.0 * (unemployment in t's region - its level at the last election)
              - 3.0 * (annual inflation - its level at the last election)
              - 0.025 * years in office
share   = exp(utility) / sum over options of exp(utility)
```

A household's change in real income is its real net income against an exponential
average over about a year (`income_change`); a type's is the average over its adults. Since
stage S13.7 half of it is the change against the household's real net income at the last
election instead (below, "Memory of income").

## Where the numbers come from

| Numbers | Source |
|---|---|
| Intercepts (`intercepts.csv`) | Fitted so that in the base month every region's shares of its adults (each bloc, and not voting) equal its 2024 shares of its electorate (`../data/elections/ge2024.csv`): exact to within 1e-12 |
| Age effects (`age_effects.csv`) | Assumptions: the 2024 election's widely reported pattern, that turnout rises with age, the young lean to the centre-left and the greens and older voters to the centre-right and the populist right. Sized so that the centre-right's odds among those 65 and over are about seven times those among 18 to 24 year olds. An ecological regression of the 2024 constituency results on Census 2021's age mix was tried first and gave impossible shares (everyone aged 25 to 34 not voting, three quarters of those over 65 voting centre-right): age, class and place cannot be told apart from constituency totals |
| The government's fundamentals | Assumptions in the range of the economic-voting literature (`docs/S5-PLAN.md`): a 1% rise in a type's real household income adds about half a point to the government's share among it; a point of unemployment takes off about a point and a half; a year in office about half a point. Each has low (half) and high (one and a half times) presets; the intercepts are fitted for each preset (`intercepts.csv`), so every preset reproduces 2024. Screening (`../SENSITIVITY.md`) finds time in office the most influential. Since stage S9.4 the income and unemployment effects are these judgements combined with their fit to the elections of 2010 to 2024 (below) |

Income quintile and work enter only through the government's fundamentals: no published
table without survey microdata gives their effect on the vote.

## What it gives

- `vote_intention` (by bloc), `government_support`, `turnout`: the polls, each month;
- `regional_intention` (by region and bloc), which S5.3 turns into seats;
- `own_support` (stage S13.7): the player's bloc's (the centre-left's) voting intention, in
  government or not. Political capital is earned on it (`../capital.toml`) and the centre of
  the board shows it, so governing in a coalition does not raise either.

In the base month the government (the centre-left bloc) has 33.9% (its 2024 share was
33.7%; the households weight regions by adults, not by registered electors) and turnout
is 59.7%. With unchanged policy the government drifts to 31.3% in five years: time in
office, and unemployment a little higher.

## Seats and government (stage S5.3)

Each month the model projects the House of Commons "if an election were held now":
every constituency's 2024 shares (`seat_shares.csv`; the "other" bloc by its best-placed
candidate, as first past the post counts candidates) are scaled by its region's swing,
the region's voting intention now over its 2024 shares (proportional swing), and the
largest share wins the seat. In the base month this gives the 2024 result exactly: 411
centre-left, 121 centre-right, 72 liberal, 18 Northern Ireland, 9 Scottish nationalist,
6 others, 5 populist right, 4 green and 4 Welsh nationalist.

A general election is held when `parliament_months` (60) have passed since the last: the
first in July 2029. Then `seats` and `seat_holder` take the projection, and a government
forms: the largest bloc, then the blocs nearest it on a left-right axis (`positions.csv`,
a judgement of where each stands on tax and spending: green -0.7, Scottish and Welsh
nationalists -0.5, centre-left -0.4, liberal -0.1, Northern Ireland and others 0,
centre-right 0.4, populist right 0.8), added until they hold 326 seats. Time in office
restarts when the governing blocs change; unemployment and inflation are measured from
the new election.

`player_governs` is false once the player's bloc (the centre-left) is out of government.
With unchanged policy for thirty years the player's bloc keeps office at every election to
2054: majorities of 373 in 2029 and 340 in 2034; in 2039 it falls short with 296 seats and
governs with the green and the two nationalist blocs (326 together), which restarts its
time in office; majorities again from 2044. Time in office counts heavily: the 2039 reset
is why 2044 goes well.

## Bills (stage S5.4)

Every change the player makes to a tax or spending lever is a bill: raising a tax rate, a
benefit or a spending bill moves policy to the left; raising a threshold or an allowance,
the Universal Credit taper or the State Pension age, to the right (`leaning` in
`households.toml` and `calibration.toml`). Policy is taken to stand where the leading
governing bloc stands. It votes for its bills; every other bloc votes for a move to the
left if it stands further left than the leader, and for a move to the right if further
right. More than 325 seats pass a bill. With 411 seats of its own the government passes
everything; in a hung parliament, a left-led government needs enough seats to its left to
raise taxes (`scenarios/hung_parliament.toml`: 324 votes, one bloc too few).

## Unemployment by region (stage S6.2)

The model has one national labour market, so unemployment by region is the national rate
times each region's relative rate in the 2024 Annual Population Survey
(`regional_unemployment_ratio`: the North East's is about 1.2 times the UK's, Northern
Ireland's about half). Voters weigh their own region's change since the last election, so
a rise in unemployment costs the government more where unemployment is high.

## Issues beyond the economy (stage S8.3)

Voters also weigh, for the blocs in government, four issues, each as its change since the
last election in a measure where 1 is how things stood: health, education and policing
(their service levels, `../functions.toml`: real spending per person served) and the
environment (the path to net zero over actual emissions, `../emissions.toml`). How much
each age band cares is a judgement (`issue_weights.csv`, in `tools/uk/voters.py`), sized so
that a 10% fall in the health service costs the government about as much among people
over 65 as a point of unemployment; the young weigh the environment most, people of an age
to have children education, older people health and policing. Voter types do not know
their party, so age stands in for leaning. `issue_weight_scale` (presets 0.5 and 1.5)
scales them all, for screening.

The issues start at zero in the base month, so the intercepts and the 2024 shares are
unchanged. With unchanged policy services wear down as the population ages and emissions
drift above their path, so the government polls a little lower: 352 seats in July 2029
(373 before the issues), still a majority; 359 since stage S9.4's fitted reactions (below). A third off health spending costs it about six
and a half points within seven months, with the recession it brings. The figures for later elections
above were measured before stage S8.


## Answers to dilemmas (stage S9.2)

`government_standing`, by voter type, is added to each type's fundamentals for the blocs in
government. It is zero until the government answers one of the questions in
`dilemmas.toml` in a way that changes it: an NHS left to ride out a winter crisis costs
0.04 among voters of 65 and over for six months, a steelworks left to close 0.05 in Wales
and Yorkshire for two years, and so on (`models/uk/README.md`, Dilemmas). The voter types'
quintile and work (`type_quintile`, `type_in_work`) are there for these effects. The base
month and the 2024 shares are unchanged.

## Groups (stage S13.4)

Eighteen interest groups, the dimension `group`, in this order: the young (18 to 34),
mid-life (35 to 64), pensioners (65 and over; the member is `pensioner`, since
`pensioners` is a household value), low incomes (the poorest household income quintile),
middle incomes (the middle three), high incomes (the richest), in work, out of work (under
65 and not in work), parents (adults in households with children), lone parents (the adult
of a lone-parent family with children), the self-employed, and seven places: Scotland,
Wales, Northern Ireland, London, the North (North East, North West, Yorkshire), the
Midlands (East and West) and the South (East, South East, South West).

**Membership** (`group_member`, by voter type and group) is exact for the groups the voter
types are made of: 1 or 0 by region, age band, quintile and work. Parents, lone parents and
the self-employed cut across the types, so for them it is the share of the type's adults in
the group, summed from the households with their current weights (`voters_parents`,
`voters_lone_parents`, `voters_self_employed`), so it follows the population as the
households are reweighted. Quintiles are of households, so the poorest quintile holds
about 15% of adults and the richest 23%.

**Approval** (`group_approval`, and a row each, `approval_<group>`) is the share of the
group's likely voters, the adults who would vote, who would vote for a governing bloc:
the model's own choice shares, summed over the voter types with each type's adults in the
group as weights. So it moves with everything the vote moves with. Weighted by likely
voters, the approvals of a partition (the age bands, the income groups, the places) give
the government's poll rating exactly, up to rounding. The government's bloc does not
stand in Northern Ireland, so approval there is nil. `group_share` (and `share_<group>`)
is the group's share of all adults.

**Drivers.** For the governing blocs a voter type's utility is identity (the region's
intercept and the age band's effect, fitted to 2024) plus performance. The performance part
is split into five drivers, each the group's mean over its adults (weights as above):

| Driver | The term |
|---|---|
| `group_driver_income` | `vote_income_effect * voter_income_change`: real household income against a year before and against the last election, half and half (stage S13.7) |
| `group_driver_jobs` | `voter_jobs`: unemployment in the type's region against the last election |
| `group_driver_prices_and_time` | `fundamentals`, inflation against the last election and time in office, less the base month's time in office (six months), the same for every group |
| `group_driver_services` | `voter_services`: health, education and policing service levels and the climate, against the last election |
| `group_driver_standing` | `government_standing`: reactions to the government's answers to dilemmas |

The five add up to the group's mean performance utility less the base month's time in
office, which the intercepts were fitted with; so all five are zero in the base month.
They are utilities (log-odds), not points of approval: a driver of -0.1 makes the
government's odds about a tenth lower among the group, all else equal.

**Households.** For each household: `household_in_<group>`, true when any of its adults is
in the group (low, middle and high incomes, parents and the places are the household's);
`household_support`, the mean over its adults of their voter type's share for a governing
bloc. The rest of a household's statement is in `../households.toml`: `household_earnings`,
`household_pensions` (state and private), `income_tax_year`, `employee_ni_year` and
`household_benefits` (Child Benefit net of the charge, and Universal Credit), each a year;
`net_income`, a month; and here `income_change`, real net income against its average over
about a year and its level at the last election.

What is estimated: the household groups come from the synthetic households, whose children
and self-employment follow the published tables they were built from
(`../households/README.md`); and approval is what the model's vote gives, with the age
effects and fundamentals above, not a poll of the group.

**Estimated groups (stage S13.5).** Five more groups follow the eighteen: motorists, home
owners, renters, drinkers and smokers. The households do not say who has a car, owns a home,
drinks or smokes, so membership is a share of each voter type's adults estimated from
published shares by income quintile and age band (`estimated_groups.csv`, the parameters
`estimated_member_<group>`), with the same rows as the other groups but no
`household_in_<group>`. Sources and estimates are in `../POLICIES.md`, Groups. The policies of
`../policies.toml` add their reactions to `government_standing` through `policy_standing`,
and the policing issue is the police service level over the policies' effect on crime
(`crime_policy_level`); both are nil, or one, with every policy as in 2024.

Stage S13.6: motorists and home owners also vary by region. Within each region the shares by
income and age are scaled so that the region's mean is in proportion to its published share
of households with a car or van (Census 2021 TS045, NISRA MS-E10, the Scottish Household
Survey) or owning their home (Census 2021 TS054, NISRA MS-E15, Scotland's Census 2022), and
the national share of adults is held where it was (79.5% and 65%). London, with the highest
incomes but the fewest cars, now has 60% motorists against 75% to 87% elsewhere, and 48%
home owners against 64% to 69%. Renters are still the rest.

## Against past elections (stage S9.4)

`tools/uk/history.py` fits the government's reactions to income and unemployment to the
general elections of 2010, 2015, 2017, 2019 and 2024 (UK Parliament's results, Open
Parliament Licence; ONS's regional real household disposable income per head and the
Annual Population Survey, OGL): for each of the four terms and the eleven regions of Great
Britain, the change in the log-odds of the senior governing party's share of the
electorate, on the change in real income growth in the year before each election and in
regional unemployment, with an effect for each term (`../data/elections/history.csv`,
`HISTORY.md` there).

The income effect comes out at 4.0 (standard error 2.7) against the judgement of 2.5; the
unemployment effect at +0.9 (3.4) against -6: regional unemployment moved too much in step
to show its effect. Fitted on the first three terms, the effects do not predict 2024's
regional pattern (a correlation of -0.14). So the data are weak evidence, and each effect
is the judgement and the fit combined, weighted by their precisions (the judgement's low
and high presets taken as a standard deviation either side): income 2.76 (presets 1.62
and 3.90), unemployment -2.96 (-0.74 and -5.21). Time in office and inflation, which only
the four term effects could show, are left as they were. With unchanged policy the
government polls 30.5% at the 2029 election, against 30.2% with the earlier judgements,
and wins 359 seats rather than 352.

## Memory of income (stage S13.7)

The playtest of `docs/S13-BALANCE.md` found that voters forgot a tax rise within one to two
years: real income was judged only against its average over about a year, while jobs, prices
and services are judged against the last election. So the dominant strategy was to raise
taxes at once and spend late. Now half of a household's `income_change` compares real net
income with that average, as before, and half with its level at the last election
(`income_at_election`, a household state set at each election and, standing in for July
2024's, in the base month, as `inflation_at_election` and
`regional_unemployment_at_election` are; `income_election_share`, 0.5, a judgement).

The fitted coefficient `vote_income_effect` (2.76, stage S9.4) is kept as it is. It was fitted
to the change in real income growth in the year before each election, which is nearer the
old one-year measure; applying it to a term-long change, half weighted, treats a lasting fall
in real income as worth about as much per point as a recent one. That is a judgement, made
because the historical fit cannot tell the two memories apart (four terms, eleven regions)
and because the rest of the voters' fundamentals already reach back to the election. The
term is nil in the base month (no memory yet) and the same as before in the second (the
year's memory and the election's level are both the first month's income), so the base month
and the fitted intercepts do not move.

What it changes: with policy unchanged, real incomes grow over the term, so the government
does a little better than before (363 seats in July 2029 against 344, without the 2025
scenario's wear of office below); in the 2025 scenario a 30% basic rate from February 2025 now
costs 26 seats at the election (330 to 304), where it cost none.

## Wear of office (stage S13.7)

`vote_wear_effect`, nil in the model, is added to the governing blocs' utility for each year
in office beyond six months (the six the government had held office in the base month, and
after a change of government its first six), so a scenario can say its government wears
faster without moving the base month or the intercepts, which are fitted to the six months
of the base month. `scenarios/2025.toml` sets it to -0.025 (its `[params]`), as much again as
the fitted `vote_tenure_effect`: with policy unchanged and the first answer to every question
the government polls 28.7% in June 2029 and keeps 330 seats in July, against 363 without it;
with the second answers 323, short of a majority. A government that governs well keeps its
majority; one that coasts is near the line or in a hung parliament. The other UK scenarios
keep the model's nil.
