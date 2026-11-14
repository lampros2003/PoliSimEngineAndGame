# Stage S5: politics

Written 2026-11-14, after S4. The roadmap's line for this stage: voters, parties as blocs,
a legislature, bills that can fail. The ballot (question 04) asked for voters and
elections plus parties and a legislature (seats, coalitions, votes on bills, a reacting
opposition), and not the full machine of ministers, factions, media and lobbies.

## Decisions

Proposed here, and taken as decided unless the owner changes them.

| Question | Decision | Why |
|---|---|---|
| Voter data | Published aggregates only: the 2024 general election results by constituency (UK Parliament's election results site, Open Parliament Licence v3.0, votes by party only, no candidate names) and Census 2021 by 2024 constituency (ONS, Open Government Licence v3.0). No survey microdata: the British Election Study and pollsters' panels need permission, which the owner has not given | The roadmap made voter data a licence decision; these sources are open and commercial use is allowed, and every number they give can be checked |
| Parties | Nine blocs, not real parties: centre-left, centre-right, liberal, populist right, green, Scottish nationalist, Welsh nationalist, Northern Ireland, other. Real parties map to blocs for calibration only (Labour to centre-left, and so on); their names never appear in the game, and a mod can rename the blocs | "Parties as blocs" is the roadmap's wording; real names raise trademark and reputational questions the owner has not settled |
| Who votes | The adults of the synthetic households aged 18 and over, grouped into 600 voter types: region (12) by age band (5) by household income quintile (5) by in work or not (2) | One population for "who gains" and "who votes how", so a policy's winners and losers are the voters who react; types keep the vote arithmetic small (the multilevel-regression-and-poststratification idea) |
| How they choose | Each voter type's utility for each bloc: a regional intercept, an age-band effect, and for the governing blocs the fundamentals: the change in the type's own real household income, unemployment and inflation since the last election, and time in office. Abstention is an option. Shares by multinomial logit | The election-forecasting literature's best-validated drivers (economy, incumbency, time for change) in the cheapest standard choice model |
| Calibration | Intercepts so that the base month reproduces the 2024 vote shares in every region; age effects from an ecological regression of 2024 constituency shares on the census age mix (England and Wales); turnout by age the same way. Fundamentals' sizes from the economic-voting literature, recorded as assumptions | Every target is a published number; the age pattern is the strongest one in 2024 and the census measures it |
| `exp` | Added to the formula language with a fixed algorithm of additions, multiplications and divisions, so the oracle and the engine agree on every machine | A logit needs it; the language left it out for exactly this reason |
| Seats | 650 constituencies. A bloc's 2024 share in each constituency is scaled by its regional share now over its regional share in 2024 (proportional swing), and the largest share wins (first past the post). Northern Ireland's 18 seats stay with the Northern Ireland bloc. The base month reproduces the 2024 seats | The standard seat projection, needing only the results above |
| Elections | Every five years from July 2024, so the first in the game is July 2029 | The fixed term the 2024 Parliament runs to |
| Government | The bloc with a majority; otherwise the largest bloc with the blocs nearest it on a left-right axis, added until they hold a majority. The player leads the centre-left bloc, in government at the start; losing government ends the game | Minimal connected winning coalitions, the simplest rule with support in coalition research; the player's position matches the 2024 result |
| Bills | Every change to a lever with a `leaning` (left or right) is a bill. Governing blocs vote for it; an opposition bloc votes for it if the change moves policy towards its side of the axis. It passes with more than half the seats; otherwise the lever keeps its value. Inputs without a leaning (world demand, market rates) are not bills | A majority government passes its bills, as in the UK; a minority or coalition government can lose them. The vote is part of the engine's step, so a scripted run and a played game agree |

## Engine work this needs

- **`exp(x)`** in the formula language (specification, oracle, engine, conformance cases).
- **Bills**: a model's `[legislature]` (seats, governing blocs, bloc positions) and a
  lever's `leaning`; the step's first part (applying scheduled lever changes) votes on
  each change. Specification, oracle, engine and tests; failed bills are reported.

The rest is model files: voter types are a dimension, their sizes and incomes come from
the households through `wsum_by`, and the seat arithmetic is dimensioned formulas over
constituencies and blocs.

## Milestones

| # | Milestone | Done when |
|---|---|---|
| S5.0 | Election and census data | The pipeline fetches the 2024 results and the census age and work tables by constituency; the extracted files reproduce the published totals by party (votes and seats) exactly; licences recorded |
| S5.1 | `exp` | Oracle and engine agree bit for bit on recorded cases across the whole range; accuracy within 2 units in the last place of the true value |
| S5.2 | Voters | The base month reproduces the 2024 vote shares of every bloc in every region within 0.5 points and turnout within 1 point; voting intention responds to the economy in the documented direction; the households' voter types add up to the electorate |
| S5.3 | Seats and government | The base month's seat projection gives the 2024 seats by bloc exactly; an election every five years; a government formed by the rule above; tests with invented results for a hung parliament |
| S5.4 | Bills | A lever change passes or fails by the vote above, identically in the oracle, the engine and the client; a test where a minority government loses a bill |
| S5.5 | Politics in the client | Polls (national and by region) on a chart, the House of Commons by bloc, the next election, election night results, failed bills explained, and the end of the game when the player loses |

## What could go wrong

| Risk | Sign | Response |
|---|---|---|
| Ecological regression gives impossible age effects (shares outside 0 to 1) | Negative or above-one shares by age | Constrain them (non-negative least squares on shares that sum to one) and report the fit |
| Proportional swing misbehaves for small parties | A bloc on 1% in 2024 wins seats on small national moves | Cap the scaling, or blend with uniform swing; reported against 2019 to 2024 as a back-test |
| Fundamentals too strong or too weak | Every government loses, or none does, in unchanged-policy runs | Size them so an unchanged-policy term loses a few points (time for change), and record the runs |
| Too much for one stage | S5.2 slips | Sex, education and tenure stay out of the voter types; the legislature is the Commons only |

## Status

| # | Status |
|---|---|
| S5.0 | Done. `tools/uk/elections.py` extracts the 2024 general election by constituency and bloc (`models/uk/data/elections/ge2024.csv`: votes, electorate, winner, and the best "other" candidate, since in two seats several independents together out-polled the winner) and Census 2021 age and economic activity for the 575 constituencies of England and Wales (`census_pcon.csv`). Votes and seats of every party equal the published totals; by bloc: centre-left 33.7% and 411 seats, centre-right 23.7% and 121, populist right 14.3% and 5, liberal 12.2% and 72. Open Parliament Licence terms still to be confirmed by the owner (`docs/data/first-country-licences.md`) |
| S5.1 | Done. `exp(x)` in the formula language by a fixed algorithm (`docs/spec/02-formula-language-v0.md`): reduction by ln 2, a degree-13 polynomial, exact scaling. Within 1 unit in the last place of the C library over 300,000 arguments; oracle and engine agree on 420 recorded cases across the range and at its limits |
| S5.2 | Not started |
| S5.3 | Not started |
| S5.4 | Not started |
| S5.5 | Not started |
