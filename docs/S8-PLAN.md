# Stage S8: what government does, and what voters see of it

Written 2026-11-14, after S7. The roadmap ended at S7; this stage follows from what the
game still lacks against the genre and against its own plans. The S3 plan asked for
"government spending by broad function", and the model has spending only by kind (pay,
purchases, investment); and voters weigh only the economy and time in office, so a policy
that does not move incomes, jobs or prices moves no votes. In the games this one follows,
the player sets a health budget and sees waiting lists, and voters care about more than
their pay.

## Decisions

Proposed here, and taken as decided unless the owner changes them.

| Question | Decision | Why |
|---|---|---|
| Order | Spending by function first, then what services deliver, then the environment, then the issues voters weigh, then the client | Each needs the one before it; the issues need outcomes to weigh |
| Spending by function | The public pay bill and purchases are split by function at their 2024-25 shares in HM Treasury's Public Expenditure Statistical Analyses (PESA, Open Government Licence): health, education, defence, public order and safety, transport, housing and environment, social protection (other than benefits), and the rest. A lever per function replaces the two aggregate levers; each function's demand goes to the industries that supply it | The genre's central screen is a budget by function, and PESA is the official split. The aggregates the economy reads stay, as sums, so the base month is unchanged |
| What services deliver | (Revised: NHS England's site, the waiting list's source, is not reachable from this environment, so the waiting list waits for the owner to allow it or fetch the file; the service levels need no new data.) Each function gets a service level: its real spending per person it serves (everyone, or the relevant age group: pupils for education, people over 65 weighing more for health) against 2024, smoothed so that a cut bites over months, not at once. Health also gets the NHS waiting list (NHS England's referral-to-treatment statistics, OGL): it grows when demand, rising with an older population, outruns capacity, which follows real health spending | A real, sourced outcome the public knows, where the data allow one; a stated index where they do not |
| The environment | Greenhouse gas emissions by industry, from output and each industry's 2024 emissions per pound of output (ONS's atmospheric emissions accounts, OGL), falling with a trend in intensity; a carbon price lever that raises revenue and speeds the fall in intensity, at the cost of higher prices | It builds on S6.4's industries, and it is the issue a whole bloc stands for |
| Issues | Voter types weigh, for the government, the change since the last election in health, education, policing and the environment, as they weigh the economy now; how much each type cares is a documented judgement by age band (older voters more on health, parents' ages more on education), and the green bloc's voters more on the environment. Each weight has low and high presets, and the intercepts are refitted so every preset still reproduces 2024 | The genre's voter groups with their own concerns, in the model's own terms; no survey microdata (BES) without the owner's permission |
| The client | The budget shows spending by function; a "Public services" panel shows each service level and the waiting list, and emissions, with their change; situations for a lengthening waiting list and for emissions above their path | Built from the catalogue and `[play]`, as everything else |

## Milestones

| # | Milestone | Done when |
|---|---|---|
| S8.0 | Spending by function | PESA's 2024-25 split in the UK model, a lever per function, the base month unchanged, government demand by function reaching the right industries |
| S8.1 | What services deliver | A service level per function and the NHS waiting list, matching 2024 in the base month; a cut in health spending lengthens the list within a year |
| S8.2 | The environment | Emissions by industry matching 2024; a carbon price that raises revenue and lowers emissions |
| S8.3 | Issues | Voters weigh services and the environment; every preset reproduces 2024; screening includes the new weights |
| S8.4 | In the client | The budget by function, the public services panel, the new situations; client tests |

## What could go wrong

| Risk | Sign | Response |
|---|---|---|
| PESA's functions do not match the national accounts' pay and purchases | The split adds to a different total | Use PESA's shares, not its levels, so the national accounts' totals stand |
| Service levels are indices nobody recognises | A player cannot tell what 104 means | Show them as "real spending per person, against 2024", and keep the sourced waiting list as the headline |
| Issue weights dominate the economy | Screening ranks them above the fundamentals | Narrow their ranges; document that they are judgements |

## Status

| # | Status |
|---|---|
| S8.0 | Done. `tools/uk/functions.py` reads PESA 2025's procurement and current spending by function (OGL; new source `pesa2025_ch5`) and estimates pay by function; nine function levers in a "Public services" group replace the pay bill and purchases levers, which are now their sums, exact at the defaults, so the base month is unchanged to the penny. Government demand by product follows each function's own mix, raked to the input-output tables' government purchases. A third off health spending brings a recession at once. Tests and the client moved from the purchases lever to the function levers |
| S8.1 | Done, without the waiting list. Each function has a service level: real spending per person served (health weighted by age, education aged 4 to 21, social care 65 and over), against the first month, followed over about six months (presets 3 and 12). With unchanged money, ageing wears health down to 95% in the 55th month; four situations (health, schools, police and courts under strain; services improving). The client shows service levels and spending by function in "Who gains, who loses". NHS England's site is not reachable here, so the waiting list waits: the owner can allow the host or add the file |
| S8.2 | Not started |
| S8.3 | Not started |
| S8.4 | Not started |
