# Stage S9: dilemmas, prices, and politics against history

Written 2026-11-14, after S8, from the owner's answers on the decision page. The owner
chose three things for this stage: events and dilemmas, taxes that reach prices, and the
voters' reactions fitted to past elections. The owner also allowed NHS England's site, so
S8's one missing piece, the waiting list, opens the stage.

## The owner's answers (2026-11-14)

| Question | Answer | What follows |
|---|---|---|
| Stage S9 | Events and dilemmas; taxes that reach prices; politics against history | This plan. A regional economy and interface polish wait |
| Losing an election | The game ends | As now |
| The model's judgements | Fine as documented; replace them with data where data turns up | S9.5 replaces the reaction to the economy and to time in office with fitted values |
| NHS waiting list | The owner allowed www.england.nhs.uk | S9.0 |
| Open Parliament Licence | Not checked yet | Stays on the list before any release |
| Parties | Descriptive blocs | As now |
| Play test | Within a week | Changes to the feel of play wait for it; this stage's engine and data work does not |
| Early Access | Decide after the play test | |
| Steam Workshop | Yes, with Early Access | Built when there is a Steamworks app |
| Second country | Not yet: finish the UK | |
| Source | Closed | |

## Decisions

Proposed here, and taken as decided unless the owner changes them.

| Question | Decision | Why |
|---|---|---|
| Order | The waiting list, then dilemmas in the engine, then the UK's dilemmas, then prices, then the fit to past elections | The waiting list is small and its data now reachable; the dilemmas' format comes before their content; prices change the economy the fit is made against, so the fit comes last |
| The waiting list | NHS England's referral-to-treatment overview (OGL): the number waiting in England, month by month. It grows when demand, which rises with the age-weighted population, outruns treatment, which follows real health spending; its 2024 level and the rate at which it clears are taken from the series | A sourced outcome the public knows, as S8 planned |
| What a dilemma is | A question put to the player when a formula first holds, with two to four answers. Each answer changes chosen formulas, for good or for a number of months, through the same `{base}` patches mods use. It is declared in the model, as situations are, and becomes ordinary elements: a lever for the answer, states for whether it is open and what was answered | Everything stays in the model's own terms: an answer's effects show in "Why", in the icon web and in the charts like any other change, and mods can add dilemmas |
| Answering | An answer is a command, like a lever change, but not a bill: the government decides it. It is legal only while the dilemma is open, and the lever goes back to 0 when the step ends. The client stops advancing when a dilemma opens and asks for an answer | The engine stays deterministic and the answer is in the save and the command list |
| Chance | A dilemma has no chance of its own. A model that wants one writes `rand()` into the dilemma's condition, from a declared random stream | The formula language already has seeded random numbers |
| The UK's dilemmas | About a dozen, each from a real kind of decision a UK government faces (a public sector pay claim, a bank in trouble, an NHS winter, a steelworks closing, a call for more defence spending, prisons full), each arising from the model's own state, with effects on the budget, the economy, services and how voter types see the government | Content the genre is known for, tied to the simulation rather than scripted |
| Taxes that reach prices | Consumer prices get a level of their own: VAT, the carbon price and customs duties pass into them over a few months, in shares that are documented judgements with presets. Higher prices lower real incomes and, through the Phillips curve and pay, feed inflation for a while. The GDP deflator stays as it is | The trade-off the S8 carbon price lacks; the genre's taxes all cost voters through prices |
| Politics against history | The voters' reactions to the economy and to time in office are fitted, by least squares on the 2010, 2015, 2017 and 2019 results by region (Parliament's election results, OPL) given the economy of each term from the hindcast (ONS, OGL), and checked on 2024. No survey microdata | The owner wants judgements replaced by data where data exist; aggregate results are what the licences allow |

## Milestones

| # | Milestone | Done when |
|---|---|---|
| S9.0 | The waiting list | The number waiting in England in the UK model, matching 2024 in the base month; a cut in health spending lengthens it within a year; a situation for a lengthening list; shown in the client |
| S9.1 | Dilemmas in the engine | `[dilemma.x]` in model format 1, expanded the same way by the oracle and the engine, with shared conformance cases; answers checked and reset by both; the catalogue lists dilemmas; the client asks for an answer when one opens |
| S9.2 | The UK's dilemmas | About a dozen dilemmas, each arising in a test run or a scripted one, each answer's effects tested |
| S9.3 | Taxes that reach prices | A VAT rise, a carbon price and a trade barrier each raise consumer prices by about their documented share; the base month unchanged |
| S9.4 | Politics against history | Fitted reactions with their errors, the 2024 check, presets from the fit's uncertainty; the sensitivity screen rerun |

## What could go wrong

| Risk | Sign | Response |
|---|---|---|
| NHS England's file layout changes | The extractor finds no series | Keep the file's name and date in the manifest; fail loudly |
| Dilemmas feel scripted | The same dilemma every game, at the same month | Conditions on the model's state, `rand()` where it helps, and `again_after` for ones that recur |
| Patches stack badly when several dilemmas change one formula | Unreadable "Why" | Each answer wraps the formula once, in a fixed order (dilemmas by name, answers in order); the trace shows the select |
| Four elections cannot pin down many reactions | Wide errors, unstable fit | Fit few parameters (the economy and time in office, not per voter type), and say how wide the errors are |
| Price pass-through double counts the Phillips curve | Inflation runs away after a VAT rise | Pass-through is a level shift spread over months; the curve sees it only through pay |

## Open questions for the play test

| Question | Now |
|---|---|
| Should each new game have its own random seed, so that chance dilemmas come at different times? | Every new game of a scenario has the scenario's seed |
| Are the dilemmas' political costs the right size? | Judgements: -0.02 to -0.05 on a group's standing, a third to most of a point of unemployment |

## Status

| # | Status |
|---|---|
| S9.0 | Done. `tools/uk/nhs.py` reads NHS England's referral-to-treatment overview series (OGL; new source `nhs_rtt`, fetched from the site's file store, since its pages answer automated requests with a browser check). In 2024 about 1.74 million referrals joined the list a month and 1.50 million treatments left it, and 3.3% of the list a month left for other reasons. `nhs.toml`: referrals grow with the population weighted by need, treatments follow real health spending (`treatment_response`, presets 0.5 and 1.5); the list starts at December 2024's 7.46 million. With unchanged money it passes the record (7.77 million, September 2023) in the 30th month and reaches 8.8 million by the 2029 election; a tenth off health spending leaves it about 2 million longer after two years. Two situations; the list is the sixth headline figure, checked by the client test against the runner |
| S9.1 | Done. `[dilemma.x]` in model format 1 (spec 06): a lever for the answer, `x_choice` and `x_age`, and states `x_answer`, `x_months` and `x_open`; each answer's `effect` wraps the formulas it names while chosen, for `months` or for good; `again_after` puts it again. An answer is a command, legal only while the dilemma is open, never a bill; the lever is back to 0 when the step ends, so saves and hashes hold it at 0. The oracle and the engine expand and check it the same way: 36 shared cases (`conformance/dilemma_cases.toml`). The catalogue lists dilemmas, translated by `[dilemma.x]` in text files. The client asks in a dialog, holds the months until an answer (a year's run stops at the month a dilemma opens), and shows "Decide" and the answer on the strip; `polisim play` asks too. An example mod, a dock strike for Valmora (`mods/dock_strike`, with French), and a client test of it |
| S9.2 | Done. Twelve UK dilemmas in `dilemmas.toml` (from `tools/uk/template/`): the pay round, an NHS winter crisis, a bank in trouble, a steelworks, a chip maker, an energy shock, a failing water company, the defence summit, full prisons, universities, floods and a climate warning. Answers change pay, procurement, subsidies, public investment, benefits, exports, investment, consumption, inflation, treatments, service targets, emissions per pound and, through a new `government_standing` by voter type, how voters see the government. Six are chances from random streams of their own. To keep formulas small when many answers change one element, the loader now moves an element's formula into a var `<element>_before_<dilemma>` before each dilemma's effects (spec 06; two new shared cases, one with 24 dilemmas on one formula). `crates/core/tests/uk_dilemmas.rs` gives every answer and checks each element moves the way the answer says |
| S9.3 | |
| S9.4 | |
