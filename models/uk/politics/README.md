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
              - 6.0 * (unemployment rate - its level at the last election)
              - 3.0 * (annual inflation - its level at the last election)
              - 0.025 * years in office
share   = exp(utility) / sum over options of exp(utility)
```

A household's change in real income is its real net income against an exponential
average over about a year (`income_change`); a type's is the average over its adults.

## Where the numbers come from

| Numbers | Source |
|---|---|
| Intercepts (`intercepts.csv`) | Fitted so that in the base month every region's shares of its adults (each bloc, and not voting) equal its 2024 shares of its electorate (`../data/elections/ge2024.csv`): exact to within 1e-12 |
| Age effects (`age_effects.csv`) | Assumptions: the 2024 election's widely reported pattern, that turnout rises with age, the young lean to the centre-left and the greens and older voters to the centre-right and the populist right. Sized so that the centre-right's odds among those 65 and over are about seven times those among 18 to 24 year olds. An ecological regression of the 2024 constituency results on Census 2021's age mix was tried first and gave impossible shares (everyone aged 25 to 34 not voting, three quarters of those over 65 voting centre-right): age, class and place cannot be told apart from constituency totals |
| The government's fundamentals | Assumptions in the range of the economic-voting literature (`docs/S5-PLAN.md`): a 1% rise in a type's real household income adds about half a point to the government's share among it; a point of unemployment takes off about a point and a half; a year in office about half a point |

Income quintile and work enter only through the government's fundamentals: no published
table without survey microdata gives their effect on the vote.

## What it gives

- `vote_intention` (by bloc), `government_support`, `turnout`: the polls, each month;
- `regional_intention` (by region and bloc), which S5.3 turns into seats.

In the base month the government (the centre-left bloc) has 33.9% (its 2024 share was
33.7%; the households weight regions by adults, not by registered electors) and turnout
is 59.7%. With unchanged policy the government drifts to 31.3% in five years: time in
office, and unemployment a little higher.
