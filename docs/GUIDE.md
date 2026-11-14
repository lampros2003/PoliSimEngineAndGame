# Playing PoliSim (test build)

You are the head of government of the United Kingdom from January 2025, leading the
centre-left bloc with 411 of the 650 seats in the House of Commons. The economy, the
public finances, 20,000 synthetic households and the voters are simulated month by month
from the published figures for 2024. The first general election is due in July 2029; lose
office and the game is over.

The test build also has Valmora, the small invented country the client was first built
on: start it with `PoliSim Valmora.bat`.

## Starting

On Windows, unpack the download and run `PoliSim.bat`. Windows may warn that the
publisher is unknown, because the build is not signed: choose "More info", then "Run
anyway". The game opens at the start of January 2025. **Help** in the top bar repeats the
essentials.

## The screen

| Part | What it shows |
|---|---|
| Top bar | The month just finished; buttons to advance one month, a quarter or a year; **Amounts a year** (amounts at an annual rate, as the public finances are published, or per month); Save, Load, Reload model, Help |
| Headline | Output (GDP), the unemployment rate, the budget balance, debt as a share of GDP and the government's poll rating, each with last month's change, a **Chart** and a **Why** button |
| Budget | Every payment into the government (revenue) and out of it (spending), this month and last |
| Who gains, who loses | Net income per household by income decile, household type or region; jobs and pay per job by industry. Each group's change on last month, with a bar |
| Politics | Voting intention for the nine blocs, the seats they hold and would hold if an election were held now, and the months to the next election |
| Policy | 56 levers in groups: spending, income tax (and Scotland's own rates), National Insurance, Child Benefit, Universal Credit, the State Pension age, VAT and corporation tax, and trade barriers with the EU, the United States, China and the rest of the world |
| Chart | Any figure over time. Dashed lines are your policy changes. Click a name in the legend to remove it |
| Why did it change? | What moved a figure last month, input by input. Press an input to follow it; Back returns |
| Connections | The web around a figure: what it depends on to the left, what it feeds to the right, each tile coloured by last month's change. Press a tile to move to it |

## How policy works

A change to a lever is a bill. You type a new value, it shows in amber, and the House of
Commons votes on it at the start of the next month. The leading governing bloc always
votes for its own bills; the others vote for a move towards where they stand (a tax rise
is a move to the left, a tax cut to the right). With 411 seats you pass everything. If
you ever govern without a majority of your own, a bill can fail, and the game tells you
the vote.

The blocs are not real parties: they are named for where they stand (centre-left,
centre-right, liberal, populist right, green, the Scottish and Welsh nationalists,
Northern Ireland's parties and others). In the first month each region votes as it did in
2024. After that each kind of voter (by region, age, income and work) weighs the change in
its real household income, unemployment in its region and inflation since the last
election, and how long the government has been in office.

## Things to try

1. **Raise the basic rate of income tax by one point** (Policy, Income tax) and advance a
   month. In Who gains, who loses, by income decile, the upper deciles lose most; by
   region, Scotland loses nothing, because it sets its own rates.
2. **Cut purchases of goods and services by a quarter** (Policy, Spending) and advance two
   years. Jobs by industry move out of public administration, education and health
   (about 380,000 of them) while unemployment and the poll rating show the cost.
3. **Put a 20% trade barrier on China** (Policy, Trade). Customs duties appear in the
   budget, about £8bn a year; exports to China fall by about 40%, and so do imports from
   it.
4. **Press Why next to the poll rating**, then open **Connections** and follow the tiles
   back to the taxes you changed: the model's own chain, from each household's income tax
   to its income, the voters' choice and the polls.
5. **Leave policy alone and advance to July 2029.** Time in office wears the government
   down, but with an economy that holds up it keeps a majority. Then try the same with
   a slump of your own making.

## Saving

**Save** keeps one saved game, including its charts. **Load** returns to it. A game
saved with older model files still loads: it carries on with the current model, and the
game says what was carried over and what started again.

## Changing the model while playing

The UK is written in text files in `game/models/uk/` (the formats are in `docs/spec/` of
the repository). Most of them are generated from the published data by the tools in
`tools/uk/`, but you can edit any number or formula, save the file and press **Reload
model**: the change takes effect from the next month, with everything else carried over.
If the file has a mistake, the game says what and where at the bottom of the screen and
carries on with the previous version.

## Known limits of this build

- One labour market for the whole country: unemployment by region is the national rate
  scaled by each region's 2024 relative rate.
- The industries share out output and jobs but do not feed back into prices or the
  economy's demand.
- No events or situations yet (a recession, a debt crisis): they come next in stage S7.
- The households are synthetic, built from published tables only, not survey records.
- The build is not signed and runs inside the Godot engine executable, not as a
  standalone program.
