# Playing PoliSim (test build)

You are the head of government of the United Kingdom from January 2025, leading the
centre-left bloc with 411 of the 650 seats in the House of Commons. The economy, the
public finances, 20,000 synthetic households and the voters are simulated month by month
from the published figures for 2024. The first general election is due in July 2029; lose
office and the game is over.

The test build also has Valmora, the small invented country the client was first built
on, and two example mods: a wealth tax for the UK, and a dock strike for Valmora, which
puts a question to you in the third month.

## Starting

On Windows, unpack the download and run `PoliSim.bat`. Windows may warn that the
publisher is unknown, because the build is not signed: choose "More info", then "Run
anyway". The start screen offers the United Kingdom and Valmora, and the mods there are
for the country you pick: tick any you want and choose **New game**, or **Continue saved
game**. Valmora can also be played in French (a test translation); the game's own buttons
stay in English. The UK opens at the start of January 2025, with the first month already
played so that every figure has a value. (`PoliSim Valmora.bat` goes straight to Valmora.)

On your first game a guide of up to five steps points at the centre of the board, a
policy, an indicator, a group and **Next month**. Esc skips it. **Menu**, then **Show the
guide again**, brings it back, and **Menu**, then **Help**, repeats the essentials.

## The board

The whole game is one screen, the board. It is a map of cause and effect, laid out as an
ellipse that reads from the outside in, from what you control to the people it reaches. It
is the screen itself: it cannot be dragged or zoomed, it fills the window under the top bar
and the strip beneath it, and only resizing the window, or a policy coming into force or
being repealed, lays it out again. Nothing docks beside it; the month's
report, the notices and the popups float over it.

| Place | What stands there |
|---|---|
| Outer rim | **Policies**, as discs, in arcs by area: Economy, Tax, Welfare, Health, Education, Law and order, Transport, Environment and energy, Housing, Foreign and trade. The area's name is set along the rim |
| Middle | **Indicators**, as rings: the figures your policies move, in the sector of their area (in two rows where the sector is crowded). They run from GDP and unemployment to crime, school results, homelessness and electric car sales |
| Group ring | **Groups** of voters: one circle of arcs round the centre, one arc a group, 23 in six families (ages, incomes, work, families, places, ways of life), the families apart and named once inside the circle. Within its family, an arc is as long as the group's share of the electorate, and never too short for its pictogram |
| Centre | The government: its approval (your party's poll rating) and its change, the months to the election and your political capital. Click it to open Parliament |
| The strip under the top bar | **Situations** in force (a recession, a record waiting list) as pennants, and questions put to you and your answers while they last |

Size says importance: nodes come in three sizes, and the biggest are the ones that matter
most (income tax, GDP, the NHS). Every policy and indicator is named at rest from a window
of 1366 by 768 up. A group's name shows when you point at it, with its approval and last
month's change; point at any node to see its value.

Colour says what a thing is, and does not change in play:

- An **indicator**'s ring is green for a good thing, the more the better (output, pay,
  productivity, homes built), red for a bad thing, the less the better (unemployment, crime,
  poverty, homelessness, the gilt yield), and blue for a figure that is neither (Bank Rate,
  the mortgage rate). A small triangle on a badge says it rose or fell last month: green
  when that was for the better, red when for the worse, ink when neither can be said. Nodes
  that moved noticeably pulse after each month.
- A **group**'s approval is a gauge just outside its arc: the share of its likely voters
  who back the governing blocs, filled from the start of the arc and full at 60% (approvals
  sit between about 20% and 50%, so a gauge to 100% would make them all look alike). It is
  green from 38%, red under 28% and mustard between. Northern Ireland, where the governing
  party does not stand, is grey with a dash.
- A **policy**'s gauge is a pale arc round its edge, filled to where its setting sits in its
  range (for a policy of several controls, the first, such as the basic rate for Income
  tax). An ochre mark and a short line on the gauge show a change waiting for a vote. A
  policy whose bill to introduce it is waiting stands as a **ghost**, with a dashed edge,
  until the vote.
- A **situation**'s pennant is green if it is good (strong growth) and red if it is bad
  (a recession); an answer you gave is blue while it lasts, and a question waiting for you is
  ochre.

**Pointing** at a node dims the rest and draws its links. A policy's links run to the
indicators and groups it moves most; an indicator's or a group's run back from the policies
that move it most. A link is green where the effect is good for what it reaches (for a
group, approval up), red where it is bad, and blue where neither can be said; a + or − by
the arrowhead says whether it rises or falls, and a thicker, faster-flowing line is a
stronger effect. The links are not drawn from a diagram: each policy is nudged by one step,
the model is run twelve months ahead, and the links are what moved. That table is measured
again after each month, starting with the policy under the pointer; meanwhile the last
month's links stay, and a node not yet measured says "measuring its effects" and has its
links drawn grey, from the model's formulas, until the measured ones replace them. A loaded
game has its links at once, from the table kept in the save. Only the strongest are drawn:
up to seven indicators and three groups for a policy, and always the budget balance if the
policy moves it.

**The key** ("?" on the top bar, or K, or **Menu**, then **The key**) is one page on what
every shape, colour and arc means, drawn by the board's own code.

## Opening a policy

Click a policy to open its popup. It names the policy and its area, says what it is, and
opens with its main control (Income tax opens with its three rates): a slider and a field
for a number, or a row of named steps for a policy that works in levels (sentencing runs
from Lenient to Tough). Further controls, such as thresholds and allowances, wait under
**More**. Rates are typed in percent, money in pounds (or with `m` or `bn` for millions and
billions), an age or a year as a whole number. Menu, **Amounts a year**, chooses whether money flows are
shown a year or a month.

A change is a **bill**. It waits, in ochre, and the House of Commons votes on it at the
start of the next month; **Undo** takes it back before then. The leading governing bloc
always votes for its own bills; the others vote for a move towards where they stand (a tax
rise is a move to the left, a tax cut to the right). With 411 seats you pass everything. If
you ever govern without a majority of your own, a bill can fail. The popup tells you the
vote before you commit: "The Commons would pass this", with the count of votes for and against.

Every bill also costs **political capital**: 5 for any bill, and up to 60 more the further
it moves a policy across its range, scaled by a weight each policy has: the big spending
lines (the NHS, schools, social care, police, pensions and benefits, public investment) weigh
3 and the main tax rates (the basic rate, VAT, National Insurance, corporation tax) 2, so a
point on the basic rate costs 6.2 and a quarter off the NHS 27.5. You start with 40 and earn
1.5 a month, up to 5 more the higher your own party's poll rating (nothing extra at 20% or
below, all of it at 40%; in a coalition only your party's rating counts) and 2 more in the
first year of a parliament, up to 100: about 4 a month at 30%. Your capital is shown at the
centre of the board. The popup says what the bill costs and what the bills already waiting
will cost; a bill that costs more than is left when its turn comes is not put to the
Commons, and the game tells you in the month's report.

Under the controls a chart shows the policy's history with your changes marked. Once you
move a control, **In a year** takes its place: the game is run twelve months ahead with
your waiting change and without it, and the table lists the difference. It starts with the
budget balance, then up to three lines of the budget and up to six indicators, whichever
move most for their size, then the five groups whose approval it moves most. Bars are
sage where the change is for the better and brick where it is for the worse. Click any row
to open that indicator or group. The forecast takes about half a second; while it works
the last figures stay, greyed, marked "measuring".

## Introducing and repealing

A policy that is not in force is not on the board. Each area with such policies has a
**New policy** node at the end of its arc, with the number to choose from; it opens a list
with a line on each policy and what the smallest step would cost in political capital.
Choose one and its popup opens with its control at "not in force": pick a setting, read
**In a year** and the vote, and press **Put to the Commons**. The policy stands on the board
as a ghost until the vote, and when the bill passes it grows onto the board. If the bill is
voted down, or you cannot afford it, it does not come in and the report says so.

A policy in force that can be switched off has a **Repeal** button in its popup, with the
cost and the vote it would get. When the repeal passes the policy leaves the board and goes
back to its area's list.

The UK starts with 38 policies in force and five to introduce: cannabis law, home
insulation, social housing, rent controls and an electric car grant. Nineteen real-life
policies were added to the model in real units or named levels, among them the legal age to
buy alcohol, fuel, alcohol and tobacco duty, a soft drinks levy, the prescription charge,
the bus fare cap, the ban on new petrol and diesel cars, the tuition fee cap, free school
meals, planning rules, the Winter Fuel Payment and the skilled worker visa salary
threshold. Each is neutral at its 2024 setting, so the first month is the 2024 country.
`models/uk/POLICIES.md` gives every source and says which sizes of effect are judgements,
which most of them are.

## Indicators and why they moved

Click an indicator to open its popup. It shows the figure large with last month's change; its
history, with a menu to lay one more indicator of the same unit over it; **Why it moved last
month**, which lists what the figure is made of and how much each input moved it (click an
input to follow it, **Back** returns); **Who gains, who loses**, the breakdowns the
scenario gives (net income by income tenth, household type and region for household income;
jobs and pay by industry; poverty by group; each public service); and **What moves it most**,
the policies that move it, each opening its own popup. The explanation is available from the
second month of a game.

The figures on the top bar open the same popups, and so does every line of the Budget and
every situation's pennant.

## The people

Click a group to meet it. Its popup shows its approval and the month's change, its history
against the country's, its share of the electorate as a hundred figures, **What is moving
them** (six drivers of its vote: their incomes, jobs where they live, prices and time in
office, public services and the climate, the government's decisions, and the public
finances) and **Policies
that matter most to them**. Under **Households** stand eight households drawn from the
group, as figures for adults and children; click one for its account for the year:
earnings, pensions, income tax, National Insurance, benefits and net income, before housing
costs. The households are synthetic, so they stand for the group and are not real people.

Five groups have no households: motorists, home owners, renters, drinkers and smokers. The
model has no household records for car, tenure, drinking or smoking, so these groups are
estimated from published shares by age and income, and their popup says so.

## The Budget and Parliament

**Budget** in the top bar opens a sheet with every payment into the government (revenue) and
out of it (spending), this month and last. Click a line for its popup.

**Parliament**, from the top bar or the centre of the board, opens the
House of Commons as rows of seats by bloc, the polls for the nine blocs with their change on
last month and the seats each would win if an election were held now, the month of the next
general election, the issues voters weigh beyond the economy (health, education, policing,
the environment) against the last election, and the country by group; click a group's row
for its popup. In a month with an election a sheet gives the results and the new
government. If your bloc is out of government the game is over: time stops, and a saved game
can still be loaded.

The blocs are not real parties: they are named for where they stand (centre-left,
centre-right, liberal, populist right, green, the Scottish and Welsh nationalists,
Northern Ireland's parties and others). In the first month each region votes as it did in
2024. After that each kind of voter (by region, age, income and work) weighs the change in
its real household income, unemployment in its region and inflation since the last
election, how long the government has been in office, and its reaction to each policy. It
also weighs the public finances: borrowing, averaged over about a year, against the last
election. Half a point of output more barely registers; each point more costs more than the
last, most among pensioners, home owners and high incomes, and borrowing well below where it
started earns a little ("Lenders' confidence").

## Interest rates, lenders and slumps

You do not set interest rates; the Bank of England does, and you live with them.

- **Bank Rate** (Economy, blue) starts at 4.75%. Each month it moves a sixth of the way
  towards what a rule asks: higher when inflation runs above 2%, lower when unemployment
  runs above its natural rate, never below 0.1% or above 15%. A borrowed boom brings dearer
  money; a tight budget brings cheaper.
- **The gilt yield** (Economy, red) is what new government borrowing costs. It moves half
  as much as Bank Rate, and on top of that lenders ask a premium when borrowing runs above
  its level at the start of the game, and give a little back when it runs below. The
  interest on the debt follows it over the years.
- **The mortgage rate** (Housing, blue) starts at 3.8%. New mortgages follow Bank Rate and
  the gilt yield half and half, and the rate on all mortgages follows them over about two
  and a half years, as fixed deals end. Households pay the change on £1.65 trillion of
  mortgages, by age and income, out of their real income, and their votes show it; firms
  pay Bank Rate's change on their loans, and invest less when borrowing is dear.
- **The lenders' crisis** comes by chance. Nothing at the start's borrowing; then a chance
  each month that rises with borrowing above the start: about 2% at a point of output above
  it, 10% at two and 22% at three, so near certain within a year at three. Then you must
  choose between an emergency budget, paying what lenders ask, or asking the Bank of England
  to buy the gilts with new money.
- **Slumps last.** Firms and the state shed staff slowly when they want fewer (about 8% of
  the gap a month) and hire faster when they want more. Long unemployment raises the
  natural rate for a time and slows hiring, and pay falls more slowly than it rises, so a
  deep slump of your own making can outlast the policy that caused it by years.
- **Homelessness** (Housing, red) is the households in temporary accommodation in England,
  126,040 in September 2024. Rent controls, more homes built and the social housing
  programme bring it down; working-age poverty, unemployment and dearer mortgages push it
  up, over about a year.
- **Productivity** (Economy, green) is output per job against its trend, 2024 = 100. It
  follows business and public investment, school results and healthy life over about five
  years, and pay and exports follow it. It moves slowly: within a point of 100 over a term.

## Advancing time and the month's report

**Next month**, **3 months** and **Year** in the top bar run the game on. A run of several
months stops at a month in which a question is put to you.

When the months you played have something to tell (a bill passed, voted down or refused for
want of capital, a policy come into force, a situation begun or ended, an election, a
question answered), the **month's report** opens as a window over the board, under the
date: those, and the four figures that moved most against their own usual movement. Several
months played at once give one report. Click a line to open its popup. The report stays
until you close it (Close, Esc, a line clicked, or the next month); a click on the date in
the top bar brings it back. An ordinary month opens no report: one line under the date says
what moved most, and goes after three seconds. Other notices (a game saved, a change
refused) use the same line; a problem stays there, in red, until clicked.

### Questions put to you

Sometimes the government must decide: a strike, a crisis. A dialog puts the question with
two or more answers, each saying what it does. No month runs until you answer; you can
close the dialog to look at the board first, and the ochre pennant **Decide** on the strip
under the top bar (or the month buttons) asks again. Your answer takes effect the next
month, for good or for the months it says, and shows as a pennant while it lasts. The UK has fifteen: the public sector
pay round in July 2025, an NHS winter crisis once the waiting list breaks its record, the
allies' defence summit, full prisons, a climate warning, and chances (a steelworks closing,
a chip maker choosing a site, an energy price shock, floods, a failing water company or
universities, and from 2028 fuel protests and small boats) whose months the game's random
seed decides; a bank in trouble comes only with a slump, and lenders refusing the gilts only
with heavy borrowing. In this build every new game of a scenario has the same seed, so the chances
come in the same months each time.

## Keys

| Key | Does |
|---|---|
| Space or Enter | Next month (not while a question waits, and not in a field you are typing in) |
| B, P | Open or close the Budget, Parliament |
| K | Open or close the key |
| Esc | Close the popup, then the month's report, then the sheet; skip the guide |

## Settings

**Menu** holds Save, Load, Reload model, **Amounts a year**, **Size of the screen**,
**Sound**, **Volume**, Show the guide again, The key and Help.

- **Size of the screen** is Automatic (chosen from the window's height) or 100% to 200%.
  The board is designed for windows from 1366 by 768 up.
- **Sound** switches the interface's few sounds on or off, and **Volume** sets them at 25%
  to 100%.

Both are kept between games.

## Things to try

1. **Raise fuel duty by 10p** (Transport, Fuel duty: type 62.95). The bill costs about 12
   political capital. In a year public receipts are up by about £4bn a year, less than the
   rise alone would give, because drivers buy less fuel; household emissions fall by about 1%; consumer inflation is a
   little higher for the year and the government's rating about 0.3 points lower. Motorists
   turn against you a little more than the country does, London least. Point at Fuel duty to see its links.
2. **Introduce an electric car grant** (Transport, **New policy**, Electric car grant:
   set £3,000 a car). It costs about £1.8bn in the first year, and in a year the
   electric share of new cars about 2.6 points higher. Put it to the Commons, play a month,
   and watch the policy grow onto the board.
3. **Make sentencing tougher** (Law and order, Sentencing: choose Tough). The prison
   population rises over two years, by about 12,600 once it has settled, and costs about
   £0.8bn a year more; crime falls about 2% over five years. Pensioners approve and the
   young do not. In a year only the start of this shows.
4. **Liberalise planning** (Housing, Planning rules: choose Liberal). Each step builds 7.5%
   more homes, about 16,500 a year, with the effect arriving over two years; Very liberal
   adds about 30,000 homes a year and lifts output by about half a per cent after five
   years. Renters and the young gain approval, home owners lose it.
5. **Raise the basic rate by a point and open High incomes** (Tax, Income tax: type 21).
   In a year income tax receipts are up by about £5bn and household income is down. Open
   the High incomes group: its approval falls by more than Low incomes'. Then open the
   Household income indicator: by region, Scotland loses nothing, because it sets its own
   rates.
6. **Cut health spending by a quarter** (Health, The NHS) and advance two years. Jobs by
   industry (the Jobs indicator) move out of health and social work, public employment
   falls with the pay bill, the NHS waiting list climbs past its record, healthy life
   expectancy falls, and unemployment, the polls and the situations show the cost. Leave
   health alone instead and the list still grows, more slowly, as the population ages.
7. **Leave policy alone and advance to July 2029**, answering the questions as they come.
   Time in office wears the government down, but with an economy that holds up it keeps a
   majority. Then try the same with a slump of your own making.

## Saving

**Menu**, **Save** keeps one saved game, including its charts. **Load** returns to it. A game
saved with older model files still loads: it carries on with the current model, and the
game says what was carried over and what started again.

## Mods

A mod adds to the model or changes it: the example, "A wealth tax", adds a lever in its
own group, which stands on the board as a policy in an area of that name, a tax in the
budget and a reaction among the richest voters. Mods live in the game's `mods` folder and
in your own, which the start screen names. A saved game remembers its mods. To make one,
see `docs/MODDING.md` in the repository: it builds the wealth tax step by step.

## Changing the model while playing

The UK is written in text files in `game/models/uk/` (the formats are in `docs/spec/` of
the repository). Most of them are generated from the published data by the tools in
`tools/uk/`, but you can edit any number or formula, save the file and press **Reload
model** in the menu: the change takes effect from the next month, with everything else
carried over. If the file has a mistake, the game says what and where and carries on with
the previous version.

The board's layout, its policies' places and the groups are described by the scenario file,
`models/uk/scenarios/2025.toml`, under `[play.web]`, which its comment block explains. A
scenario without one gets a board made from the model's own levers and headline figures,
as Valmora does: it has no groups and no policies to introduce.

## Known limits of this build

- One labour market for the whole country: unemployment by region is the national rate
  scaled by each region's 2024 relative rate.
- The industries share out output and jobs but do not feed back into prices or the
  economy's demand.
- Situations are reported, but have no effects of their own: a recession hurts through
  incomes and jobs, as it does in the model's economy.
- The households are synthetic, built from published tables only, not survey records. They
  carry no housing costs, tenure, car or industry of work, so a household's account is
  before housing costs.
- Most sizes of a policy's effect are documented judgements around published 2024 figures
  (`models/uk/POLICIES.md`), and voters' reactions to each policy are judgements too.
- Free school meals and the Winter Fuel Payment change public spending and voters'
  reactions, but not the incomes of the households.
- Groups are built from voter types, so they cannot be sharper than the types: where a type
  holds both owners and renters, rent controls move owners' approval less than renters'.
- The build is not signed and runs inside the Godot engine executable, not as a
  standalone program.
