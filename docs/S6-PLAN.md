# Stage S6: depth and calibration

Written 2026-11-14, after S5. The roadmap's line for this stage: full industry detail,
regions, trading blocs, low, central and high presets, sensitivity screening. The plan
for S5 left the icon web here (the map of causes and effects the genre is known for).

## Decisions

Proposed here, and taken as decided unless the owner changes them.

| Question | Decision | Why |
|---|---|---|
| Order | Presets and sensitivity first, then the icon web, then regions, trading blocs and industry detail | The first two need no new data and tell us which of the rest matters; the last three each need a new published source |
| Presets | Every behavioural parameter of the UK model gets `low`, `central` and `high` values: the economy's (spending out of income and savings, hiring, prices and pay, interest, investment) and the voters' (the fundamentals). Central is today's value; low and high are documented ranges, from the literature where it gives one and a stated judgement where it does not | Format 0 already carries presets; the UK model only uses them for the population's mortality |
| Screening | One factor at a time and elementary effects (Morris) on a fixed design, run on the engine: each parameter to low and high, alone and along 20 random trajectories, on five outcomes after five years (GDP, unemployment, borrowing, debt, the government's poll rating) and the first election's seats | Cheap (a few hundred runs of 60 months, under a minute on the engine), standard, and it ranks parameters by influence, which is what calibration effort should follow |
| Icon web | The catalogue gives each value's inputs (the names its formula reads). The client shows a web around any value: its inputs on the left, what it feeds on the right, each as a tile with its value and last change, coloured by the direction of the change, clickable to move along | The model already knows its dependency graph exactly; showing it is the genre's way of explaining the simulation, and it complements "why did it change" |
| Regions | Employment by region: the rake's people-in-work margin becomes regional (Labour Force Survey employment by region, Nomis, OGL), so unemployment has a regional figure, which the voters' fundamentals then use for their own region | The households and voters are already regional; their employment is not |
| Trading blocs | Four partners (the EU, the United States, China, the rest of the world) for exports and imports, from ONS trade by country (the Pink Book, OGL); each partner's demand grows at its own rate, a lever per partner for trade barriers | The ballot asked for a few coarse trading blocs |
| Industry detail | Employment and pay by industry (ONS, OGL), so that demand for an industry's products moves its employment; 15 industries stay | "Full" detail at 104 products would cost a lot of screen and data for little play |

## Milestones

| # | Milestone | Done when |
|---|---|---|
| S6.0 | Presets and screening | Low, central and high values for every behavioural parameter, documented; `tools/uk/screen.py` writes a report ranking parameters by their effect on each outcome; the central preset is unchanged |
| S6.1 | The icon web | The catalogue lists each value's inputs; the client shows the web around any value and moves along it; a client test walks from a lever to the poll rating |
| S6.2 | Regions | Employment and unemployment by region, matching the Labour Force Survey in the base month; voters weigh their own region's unemployment |
| S6.3 | Trading blocs | Exports and imports by partner matching 2024 in the base month; a lever per partner |
| S6.4 | Industry detail | Employment by industry matching 2024 in the base month, moving with each industry's output |

## What could go wrong

| Risk | Sign | Response |
|---|---|---|
| Ranges with no basis | A low or high value nobody can source | Say so in the table, and keep the range narrow |
| One parameter dominates every outcome | Screening shows it | Calibrate it first, against the hindcast |
| The web is unreadable for values with many inputs | More than a dozen tiles on a side | Show the largest by recent effect, the rest behind a "more" |

## Status

| # | Status |
|---|---|
| S6.0 | Done. Fourteen behavioural parameters and the voters' four fundamentals have low, central and high presets (`tools/uk/assumptions.toml`, `tools/uk/voters.py`); each preset derives its own share of income spent and fits its own regional intercepts, so every preset reproduces the base month, polls included, and the central one is unchanged. `tools/uk/screen.py` runs 191 five-year runs on the engine in about 90 seconds and writes `models/uk/SENSITIVITY.md`: world demand and productivity growth drive GDP, borrowing and debt; the natural rate drives unemployment; time in office drives the polls and the 2029 seats (some 30 seats a level), so it is the first to calibrate |
| S6.1 | Done. The catalogue lists each value's inputs (from the compiled formulas; flows for accounts), the bridge passes them on, and a "Connections" tab beside "Why did it change?" shows the web around any value as tiles with their values and changes, pressing one to move (`client/scripts/web_panel.gd`). The client test walks from the basic rate to the poll rating in eleven steps, the model's own chain: each household's income tax, net and real income, its change, the voter types' utility and choice, the electorate's shares, voting intention (`client/tests/web_walk.gd`) |
| S6.2 | Not started |
| S6.3 | Not started |
| S6.4 | Not started |
