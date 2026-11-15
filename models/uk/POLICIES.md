# Real policies and indicators (stage S13.5)

`policies.toml` (copied from `tools/uk/template/policies.toml` by `tools/uk/calibrate.py`)
adds nineteen policies in real units or levels, six indicators, and the reactions of the
interest groups to each policy; `tools/uk/voters.py` adds five estimated groups. This file
gives, for each, its 2024 setting and source, how its money is sized, every effect with its
size, and whether that size comes from a named source or is a judgement. Most sizes are
judgements: the published evidence gives the 2024 levels and a few elasticities, rarely the
effect of a policy on an outcome in this model's terms.

Sources are UK official statistics under the Open Government Licence v3.0 unless marked
otherwise. A figure marked *secondary* was read in a report of the source, not on the
source's own page; *estimate* means no published figure was found and the number is ours.

## How the policies reach the model

Every policy is neutral at its 2024 setting: each reaches the rest of the model through one
term that is zero, or a factor of one, at the defaults, so every value the model had before
is unchanged to the last digit (the first 24 months of `scenarios/2025.toml`, all 371 earlier
result columns compared) and the hindcast, which has no policies, reproduces its committed
results. The terms (added through the generators, `tools/uk/calibrate.py`'s fills, and the
templates):

| Term | Where | What it carries |
|---|---|---|
| `policy_duties` | `production_taxes` (economy.toml) and the tax wedge on consumer prices (prices.toml) | Fuel, alcohol and tobacco duty, the soft drinks levy and a cannabis tax against 2024's; firms pay them and pass them on to shop prices in full |
| `policy_charges` | `other_receipts` | Prescription charges against 2024's |
| `policy_purchases` | `procurement` | Prisons, the public cost of tuition fees, free school meals |
| `policy_investment` | `public_investment` | Home insulation, social housing |
| `policy_subsidies` | `subsidies` | The electric car grant, the bus fare cap |
| `policy_benefits` | `benefits` | The Winter Fuel Payment |
| `homes_policy_level` | `dwellings`, households' investment in homes | Planning rules and rent controls |
| `household_emissions_factor` | `household_emissions` (emissions.toml) | Less driving, more electric cars, insulated homes |
| `policy_migration_factor`, `policy_labour_force_growth` | net arrivals (population.toml), the labour force (model.toml) | The visa salary threshold |
| `health_demand_factor` | `referrals` (nhs.toml) | Smoking and alcohol harm |
| `policy_standing` | `government_standing` (politics.toml) | The groups' reactions |
| `crime_policy_level` | the policing issue voters weigh (politics.toml: the police service level over it) | The policies' effect on crime |

Because the money goes through existing flows, every identity holds and the budget shows it:
a duty rise is in "Other taxes on production" and public receipts, a grant in subsidies and
public spending. Spending policies are in 2024 prices and grow with the trend index as other
spending does; duties stated as multiples of 2024's rates grow with it too; fuel duty, the
prescription charge, the fee cap, the bus fare cap, the grant and the visa threshold are
nominal amounts, as they are set in law.

Each effect moves with inertia: a state follows its target over a stated number of months,
so a policy's effect builds over months and years. Bills cost political capital as any lever
does (`capital_weight` below scales the cost of moving across the whole range); a level policy
moved one step at a time is affordable, a jump across the whole range usually is not.

## The policies

| Policy | Lever (unit) | 2024 setting | Range | Leaning | Capital weight | Area |
|---|---|---|---|---|---|---|
| Legal age to buy alcohol | `drinking_age` (years) | 18 | 16 to 21 | right | 0.5 | Law and order |
| Sentencing | `sentencing` (level) | 2, as now | 0 lenient to 4 tough | right | 0.8 | Law and order |
| Cannabis law | `cannabis_law` (level) | 0, illegal | 0 illegal, 1 decriminalised, 2 legal and taxed | left | 1.0 | Law and order |
| Alcohol duty | `alcohol_duty` (multiple of 2024 rates) | 1 | 0.5 to 2 | left | 0.6 | Health |
| Tobacco duty | `tobacco_duty` (multiple) | 1 | 0.5 to 2 | left | 0.4 | Health |
| Soft drinks levy | `sugar_levy` (multiple) | 1 | 0 to 3 | left | 0.2 | Health |
| Prescription charge | `prescription_charge` (£ an item) | £9.90 | £0 to £20 | right | 0.3 | Health |
| Fuel duty | `fuel_duty` (pence a litre) | 52.95 | 0 to 100 | left | 1.2 | Transport |
| Electric car grant | `ev_grant` (£ a car) | £0 | £0 to £6,000 | left | 0.5 | Transport |
| Bus fare cap | `bus_fare_cap` (£ a journey) | £2 | £1 to £5 | right | 0.3 | Transport |
| Home insulation programme | `insulation_programme` (£ a month, 2024 prices) | £0 beyond 2024's schemes | up to £4.8bn a year | left | 0.5 | Environment and energy |
| Ban on new petrol and diesel cars | `petrol_ban_year` (year) | 2030 | 2028 to 2040 | right | 0.6 | Environment and energy |
| University tuition fee cap | `tuition_fee_cap` (£ a year) | £9,250 | £0 to £15,000 | right | 1.0 | Education |
| Free school meals | `free_school_meals` (level) | 0, means-tested | 0, 1 all on Universal Credit, 2 all pupils | left | 0.5 | Education |
| Planning rules | `planning_rules` (level) | 2, as now | 0 very restrictive to 4 very liberal | right | 1.0 | Housing |
| Social housing programme | `social_housing` (£ a month, 2024 prices) | £0 beyond 2024's | up to £6bn a year | left | 0.6 | Housing |
| Rent controls | `rent_controls` (level) | 0, none | 0 none, 1 capped rises, 2 strict | left | 1.0 | Housing |
| Winter Fuel Payment | `winter_fuel_payment` (level) | 1, means-tested | 0 none, 1 means-tested, 2 universal | left | 1.0 | Welfare |
| Skilled worker visa salary threshold | `visa_threshold` (£ a year) | £38,700 | £20,000 to £60,000 | right | 0.8 | Foreign and trade |

Dropped: **the minimum wage**. The household records have earnings but not hours, so a rate
an hour cannot be applied to them soundly, and a national approximation would duplicate the
pay the labour market already sets. **Public-sector workers** as a group: no policy here
needs them, and their shares by region were not found.

### Legal age to buy alcohol

18 in 2024. Regulation only: no money. Each year above 18 cuts alcohol drunk by 0.3% (people
under 21 drink about a twentieth of it and a higher age cuts theirs by about a quarter: a
judgement), crime by 0.5% (a judgement from the American studies of the drinking age of 21,
Carpenter and Dobkin, Wagenaar and Toomey, cited only), and through alcohol drunk, alcohol
harm and some more crime (below). Reactions: the young -0.02 for each year above 18 and
+0.005 below; drinkers -0.01 above; pensioners +0.005 above and -0.01 below. Measured: at 21,
crime 1.0% lower after a year and 1.6% after five, alcohol deaths 171 fewer a year after five,
the young's approval 1.8 points lower and the government's rating 0.5 points.

### Sentencing

Level 2 is 2024's practice. Each step moves the prison population's target 8% from the
85,372 of 31 December 2024 (Ministry of Justice, Offender management statistics quarterly,
https://www.gov.uk/government/collections/offender-management-statistics-quarterly), followed
over 24 months: two steps tougher holds about 100,000, near the Ministry's central projection
of 100,800 for March 2029 (Prison population projections 2024 to 2029). Money: each prisoner
above or below 2024's at £51,724 a year, the overall average cost of a prison place in
2022-23 (Ministry of Justice, Costs per place and costs per prisoner, given in a
parliamentary answer: *secondary*), in public purchases. Effect: crime falls 0.15 for each
unit rise in the prison population against 2024's (incapacitation; a judgement, well below
American estimates made at far higher imprisonment). Reactions: pensioners +0.01 a step
tougher, the young -0.01. Measured at tough (4): 12,600 more prisoners and £0.78bn a year
more after five years, crime 2.0% lower.

### Cannabis law

Illegal in 2024. Money: legal sale raises £1bn a year in 2024 prices (a judgement within the
range of published estimates, *estimate*), as a tax on production. Effects: crime 0.5% lower
when decriminalised and 1.5% when legal (a judgement: less trade for criminal markets; the
Crime Survey does not count possession itself), healthy life 0.03 years shorter when legal (a
judgement), over three years. Reactions for each step: the young +0.015, pensioners -0.02,
parents -0.005. Measured with legal sale from the start: £1.0bn a year, crime 1.5% lower after
five years, the young's approval 0.7 points higher and pensioners' 0.6 lower.

### Alcohol duty

2024's rates, which raised £12.6bn in 2023-24 (HMRC, Alcohol Bulletin,
https://www.gov.uk/government/statistics/alcohol-bulletin, *secondary*). Duty is about a
quarter of the price of a drink (a judgement across on- and off-trade), so prices rise 25%
when duty doubles, and alcohol drunk falls at an elasticity of -0.5, a judgement of the
average of HMRC's own-price elasticities (Working Paper 16, Sousa 2014,
https://assets.publishing.service.gov.uk/media/5a7db32b40f0b65d88633e1c/HMRC_WorkingPaper_16_Alcohol_elasticities_final.pdf:
from -0.08 for wine bought in shops to -1.25 for spirits in pubs), over three months.
Receipts are the 2024 receipts times the multiple times alcohol drunk. Alcohol harm follows
alcohol drunk at twice the proportion over two years (a judgement: Scotland's minimum unit
pricing cut sales 3% and alcohol-specific deaths an estimated 13.4%, Public Health Scotland
2023, https://publichealthscotland.scot/publications/evaluating-the-impact-of-minimum-unit-pricing-for-alcohol-in-scotland-a-synthesis-of-the-evidence/,
*secondary*; that policy bore on the heaviest drinkers, a duty is spread wider). Crime rises
0.1 for each unit of alcohol drunk (a judgement: alcohol is involved in about two fifths of
violent incidents). Reaction: drinkers -0.04 for each multiple above 1. Measured at 1.5: £6.1bn
a year more after five years, alcohol drunk 6% lower, 1,190 fewer alcohol deaths a year, crime
0.6% lower, healthy life 0.07 years longer, the rating 0.35 points lower after a year.

### Tobacco duty

2024's rates, £7,926m in 2024-25 (HMRC, Tobacco Bulletin,
https://www.gov.uk/government/statistics/tobacco-bulletin, *secondary*). Duty and the VAT on
it are about seven tenths of a packet's price (a judgement from the 2024 rates). Duty-paid
sales fall at an elasticity of -1 (an *estimate* in line with HMRC's published work, which
includes smuggling and buying abroad), over six months; the share of adults who smoke, 10.6%
in 2024 (ONS, Adult smoking habits in the UK 2024,
https://www.ons.gov.uk/peoplepopulationandcommunity/healthandsocialcare/healthandlifeexpectancies/bulletins/adultsmokinghabitsingreatbritain/2024),
at -0.3 (a judgement), over two years. So a higher duty raises little: at 1.5, £0.4bn more
after a year and £0.2bn less after five, as sales fall. Smoking costs 0.15 years of healthy
life for each point of prevalence and adds to referrals for treatment (about 4% of hospital
work: judgements). Reaction: smokers -0.06 for each multiple above 1. Measured at 1.5:
smoking 9.6% after five years, healthy life 0.15 years longer, referrals 0.4% fewer.

### Soft drinks levy

2024's rates, £338m in 2023-24 (HMRC, Soft Drinks Industry Levy statistics, *secondary*).
Levied volume falls by half the levy's proportional rise over a year, as makers cut sugar
below its thresholds (a judgement; OHID, Sugar reduction in drinks 2015 to 2024, found sugar
per 100ml down 47% under the levy). Healthy life 0.02 years for each multiple (a judgement).
Reactions: low incomes and parents -0.005 each for each multiple above 1. Measured at 2: £135m
more in the first year and almost nothing after five, as drinks are reformulated.

### Prescription charge

£9.90 an item in England from 1 May 2024 (Department of Health and Social Care,
https://www.gov.uk/government/news/nhs-prescription-charges-from-1-may-2024), raising about
£600m a year (the Department's figure, *secondary*), so about 61m items paid for a year. Items
paid for fall a tenth for each doubling of the charge (a judgement: most who pay hold a
prepayment certificate). Money in other public receipts. Healthy life 0.03 years shorter for a
doubling (a judgement: some go without). Reactions: mid-life and low incomes -0.02 each for a
doubling (most pensioners and children are exempt). Measured at £15: £0.26bn a year more, the
rating 0.15 points lower.

### Fuel duty

52.95 pence a litre on petrol and diesel since March 2022, £24.4bn in 2024-25 (OBR, Fuel
duties, https://obr.uk/forecasts-in-depth/tax-by-tax-spend-by-spend/fuel-duties/,
*secondary*), so about 46bn litres a year. The pump price, about 140p in 2024 (a judgement),
rises by the duty with VAT on it; fuel bought falls at an elasticity of -0.4 over a year (a
judgement between the short-run -0.25 and long-run -0.6 of the transport literature, Goodwin,
Dargay and Hanly 2004, cited only). Receipts are the rate on the fuel now bought, so electric
cars from any policy reduce them. Driving is 45% of households' own emissions (a judgement),
so they fall with fuel bought and with the policies' electric cars on the road. The duty
passes in full to shop prices (the tax wedge). The electric share of new cars rises half a
point for 10p (a judgement). Reactions: motorists -0.004 for each penny above 52.95 and
+0.002 for each penny below (a rise is resented more than a cut is thanked); the young
+0.0005 a penny. Measured at 62.95: £4.0bn a year more after a year, £3.6bn after five;
households' emissions 1.2% lower after a year and 1.7% after five; consumer inflation 0.06
points higher for a year; the rating 0.8 points lower.

### Electric car grant

None in 2024: the plug-in car grant ran from 2011 to June 2022, more than £1.4bn for nearly
half a million vehicles (gov.uk, *secondary*). Money: the grant on every electric car sold
(2.0 million new cars a year, DfT), as a subsidy. Effect: £3,000, about 7% off an electric
car, adds 3 points to the electric share of new cars and £6,000 another 1.5, over six months
(a judgement: a demand elasticity near -1.5, saturating; OZEV's evaluation of the grant found
it mattered most early). The extra electric cars join the 34 million on the road at the rate
new cars do (an *estimate* from DfT's licensing statistics) and cut households' driving
emissions and fuel duty. Reactions per £1,000: the young +0.005, motorists +0.002. Measured at
£3,000: £1.8bn in the first year and £5.0bn a year after five (more cars are electric), the
share 2.6 points higher after a year, fuel duty £0.19bn a year lower after five, the rating
0.2 points higher.

### Bus fare cap

£2 a single journey in England outside London in 2024 (DfT). The DfT's evaluation of the
first ten months found about 5% more journeys (https://assets.publishing.service.gov.uk/media/681b355b9ef97b58cce3e4e0/evaluation-of-the-first-10-months-of-the-2-bus-fare-cap.pdf,
*secondary*). Money: support to bus companies for the gap between the uncapped fare, about
£2.80 (a judgement), and the cap, on 375m journeys a year, sized so that the £2 cap costs
about £0.3bn a year (an *estimate*: its cost was not found published), as subsidies. No
effect on emissions is modelled: the switch from cars is small. Reactions: low incomes and
the young -0.01 each for each pound above £2. Measured at £1: £0.38bn a year more.

### Home insulation programme

None beyond 2024's schemes (ECO, the Great British Insulation Scheme, whose spending was not
found). About £5,000 of public money treats a home (a judgement across loft, cavity and solid
wall insulation), saving 15% of its heating (a judgement); heating is 55% of households' own
emissions (a judgement), and there are about 28.4 million households (an *estimate*). An
insulated home saves about £180 a year on bills (a judgement, shown as
`energy_bills_saved`). Money as public investment. Reactions per £1bn a year: low incomes
+0.008, the young +0.005. Measured at £2bn a year: 400,000 homes a year; households'
emissions 0.5% lower after five years, bills £0.4bn a year lower.

### Ban on new petrol and diesel cars

2030, as the government restored it in 2025 (2035 under the previous government; the default
is the year in force at the start of play). The electric share of new cars follows a path
from 2024's 19.1% to 80% in the year of the ban, shaped like the zero-emission vehicle
mandate's targets (28% for 2025, 33% 2026, 38% 2027, 52% 2028, 66% 2029, 80% 2030; DfT,
https://www.gov.uk/government/publications/vehicle-emissions-trading-schemes-vets-order-2023-updates/updates-to-the-vehicle-emissions-trading-schemes-vets-order-2023,
*secondary*), a year behind them at first as 2025's sales fell short; then all new cars five
years later. Only the difference from the 2030 path changes emissions and fuel duty, so the
base run is unchanged. Reactions: for each year earlier than 2030, motorists -0.01 and the
young +0.012 (most of the young are motorists too, so on balance they gain); for each year
later, motorists +0.004 and the young -0.012. Measured at 2028:
the share 6.7 points higher after a year; households' emissions 1.9% lower and fuel duty
£1.1bn a year lower after five; the rating 0.3 points lower.

### University tuition fee cap

£9,250 in 2024-25. Fee income was about £10bn (Wonkhe, not OGL, cited only), so about 1.08
million students pay the full fee (an *estimate*). Fees are paid with student loans, which
are financial transactions the model does not have; the public cost is the three tenths of
the loans never repaid (a judgement), counted in public purchases when the fee is charged.
Students fall a tenth for each doubling of the fee (a judgement: the tripling of 2012 did
little to numbers). Reactions: for each £1,000 above £9,250 the young -0.01 and parents -0.003
(the dilemma "universities near bankruptcy" gives higher fees -0.03 among the under-35s); for
each £1,000 below, the young +0.005. Measured at £12,000: £0.78bn a year, 32,000 fewer
students paying, the young's approval 0.7 points lower.

### Free school meals

In England in 2024 for the poorest families (24.6% of pupils in January 2024, DfE,
*secondary*) and all infants. Level 1 extends them to all families on Universal Credit
(announced for September 2026), about half a million more pupils (an *estimate*); level 2 to
all pupils, about 5.5 million more (an *estimate*: 9 million pupils less 2.1 million
eligible and 1.3 million infants). A meal costs £2.61 over 190 days, £496 a year (*secondary*),
as public purchases. Attainment rises 0.2 points at level 1 and 0.8 at level 2 (judgements;
studies of universal meals found small gains). Families' incomes are not changed: the
households do not hold benefits in kind. Reactions for each step: parents +0.01, lone
parents +0.02 more, high incomes -0.003. Measured at level 2: £2.8bn in the first year,
attainment 0.7 points higher after five years.

### Planning rules

Level 2 is 2024's rules (the National Planning Policy Framework of December 2024). Each step
toward liberal builds 7.5% more homes, followed over two years (a judgement from the OBR's
estimate that the 2024 reforms add about 170,000 homes over five years, some 15%;
https://obr.uk/box/alternative-scenarios-for-housebuilding/, *secondary*). Households'
investment in homes follows the same factor, so construction and output rise: at very liberal
(4), homes built 30,000 a year higher and output 0.56% higher after five years, more than the
OBR's 0.2% because the model has no crowding out of other investment. Reactions: for each
step toward liberal, home owners -0.01, renters +0.008 and the young +0.005; toward
restrictive, home owners +0.005, renters -0.008, the young -0.005.

### Social housing programme

None beyond 2024's programmes (the Affordable Homes Programme's spending was not found).
About £150,000 of public money builds a social home (a judgement), the homes following the
money over two years. Money as public investment, so construction and output rise too.
Reactions per £1bn a year: renters +0.01, low incomes +0.005. Measured at £2bn a year: 12,000
more homes a year after five years, output 0.09% higher, the rating 0.2 points higher.

### Rent controls

None in England in 2024 (Scotland capped private rent rises at 3% in 2023-24). Capped rises
cut private homes built 2%, strict controls 6% (judgements: the evidence, mostly American,
finds controlled rental housing shrinks; no evaluation of Scotland's cap was found), with
households' investment in homes. No money. Reactions for each step: renters +0.03, home
owners -0.01, the self-employed -0.005. Measured with strict controls from the start: 12,000
fewer homes a year after five years, output 0.2% lower, renters' approval 0.4 points higher.

### Winter Fuel Payment

£200 or £300 a winter. In 2024 it was limited to pensioners on Pension Credit and a few other
benefits, cutting recipients from about 11.4 million to about 1.5 million and saving about
£1.4bn (as reported, *secondary*; the DWP's own figures were not found). Level 2 pays every
pensioner, £1.4bn a year more; level 0 pays none, about £0.4bn a year less (an *estimate*),
as benefits. Pensioners' real incomes on the household records are not changed: the
records hold no Winter Fuel Payment. Reaction: pensioners +0.04 for paying every pensioner and
-0.04 for paying none (the 2024 means test was much resented). Measured universal: £1.4bn a
year, pensioners' approval 0.7 points higher.

### Skilled worker visa salary threshold

£38,700 from 4 April 2024, up from £26,200 (Home Office, *secondary*). The Home Office reckoned
the new rules would have stopped about 300,000 of the visas issued, with dependants
(https://assets.publishing.service.gov.uk/media/6581835023b70a0013234bcd/Legal+Migration+Statement+4th+December+2023+-+Estimated+Volume+Impacts.pdf),
and said that was not an estimate of net migration. A judgement: about a third of such a
change shows in net migration, so net migration a year follows a curve of the threshold
against 2024's, +100,000 at £20,000 and -110,000 at £60,000, followed over a year. Net
arrivals by region and age scale with it in the population model, so the households,
taxes and services follow; six tenths of the net migrants join the labour force (a
judgement). No money. Reactions for each £10,000 above £38,700: pensioners +0.01, the young
-0.01, the self-employed -0.005. Measured at £50,000: net migration 58,000 a year lower and
the labour force 142,000 smaller after five years, unemployment 0.07 points lower and output
0.04% lower.

## The indicators

| Indicator | Row | Base month | Source of the 2024 level | Moves with |
|---|---|---|---|---|
| Crime | `crime_incidents` | 9.2 million incidents a year | ONS, Crime in England and Wales, year ending June 2025 (https://www.ons.gov.uk/peoplepopulationandcommunity/crimeandjustice/bulletins/crimeinenglandandwales/yearendingjune2025): the Crime Survey's headline 9.2 million in the year to June 2024 | The police service level, sentencing, alcohol, the drinking age, cannabis law |
| Healthy life expectancy | `healthy_life_expectancy` | 60.8 years | ONS, Health state life expectancies, UK, 2022 to 2024 (https://www.ons.gov.uk/peoplepopulationandcommunity/healthandsocialcare/healthandlifeexpectancies/bulletins/healthstatelifeexpectanciesuk/latest): men 60.7, women 60.9; official statistics in development | The health service level, smoking, alcohol harm, the levy, prescriptions, cannabis |
| School attainment | `school_attainment` | 45.9% | DfE, Key stage 4 performance 2023/24 (https://explore-education-statistics.service.gov.uk/find-statistics/key-stage-4-performance/2023-24): grade 5 or above in English and maths, England | The education service level, free school meals |
| Homes built | `homes_built` | 221,070 a year | MHCLG, Housing supply: net additional dwellings, England, 2023 to 2024 (https://www.gov.uk/government/statistics/housing-supply-net-additional-dwellings-england-2023-to-2024) | Planning rules, rent controls, social housing |
| Net migration | `net_migration_annual` | 739,015 a year | The population model's net arrivals, from ONS's mid-2024 estimates; ONS put net migration in the year to June 2024 at 739,000 (Long-term international migration, provisional, year ending December 2024) | The visa salary threshold |
| Electric share of new cars | `ev_share` | 19.1% | DfT, Vehicle licensing statistics 2024 (https://www.gov.uk/government/statistics/vehicle-licensing-statistics-2024): 382,000 zero-emission cars of 2.0 million new (SMMT's 19.6% is on another basis, not OGL) | The ban year, the grant, fuel duty |

Inputs shown as rows too: `prison_population` (85,372), `smoking_prevalence` (10.6%),
`alcohol_deaths` (10,473 alcohol-specific deaths registered in the UK in 2023, ONS,
*secondary*), `alcohol_use`, `fuel_volume`, `homes_insulated`, `energy_bills_saved`,
`fee_paying_students_now`.

**Crime** is 9.2 million times one less 0.3 times the change in the police, courts and
prisons service level (a judgement from studies of police numbers and crime, such as Draca,
Machin and Witt 2011, cited only), times the policies' effect, which follows them over a year.
With unchanged money the police service wears down as the population grows, so crime drifts
up about 1.4% in five years. Voters weigh the policies' effect with the policing service
level: the policing issue is the service level over `crime_policy_level`.

**Healthy life expectancy** is 60.8 years plus 3 years per unit of the health service level
(a judgement: a tenth more care per person needing it adds about a third of a year), less 15
years per unit of the smoking share and 0.6 per unit of alcohol harm, plus the smaller
effects above. With unchanged money it falls about 0.2 years in five as the health service
wears down. Smoking and alcohol harm also change referrals for treatment (about 4% and 2% of
hospital work: judgements).

**School attainment** follows 45.9% plus 0.15 per unit of the education service level (a
judgement: a tenth more spending per pupil adds about 1.5 points) and free school meals,
over two years.

**Homes built** is 221,070 times the policies' level, plus the social homes of the programme.
With the policies as in 2024 it stays at 221,070: the model has no house prices.

**Net migration** is the population model's own net arrivals, 739,015 a year (the rate of the
year to mid-2024), times the policies' factor; the indicator and the population agree because
they are the same number. ONS's later estimate for the year to December 2024 was 431,000; the
population model keeps its mid-2024 rate (a known weakness in `README.md`).

**The electric share of new cars** follows the path to the ban described above, plus the
grant's and fuel duty's effect.

## Groups

Five groups are estimated from published shares by income fifth or age band and added to
the `group` dimension after the eighteen of stage S13.4, with the same rows (`approval_<group>`,
`share_<group>`, the drivers). Membership is a share of each voter type's adults
(`politics/estimated_groups.csv`, written by `tools/uk/voters.py`), not a fact about a
household, so there is no `household_in_<group>` for them. The shares are an age band's figure
times an income fifth's factor, scaled so the share of all adults matches the published total
where one is given, at most 98%:

| Group | Base month share | Approval | From |
|---|---|---|---|
| Motorists | 79.5% | 34.1% | DfT, National Travel Survey 2024, household car availability (https://www.gov.uk/government/statistics/national-travel-survey-2024/nts-2024-household-car-availability-and-trends-in-car-trips): 60% of the poorest fifth of households and 86% of the richest have a car; the middle fifths (73%, 83%, 88%) are *estimates* read from its chart; 78% of all households. Household shares applied to adults |
| Home owners | 65.0% | 32.2% | English Housing Survey 2023-24 (https://www.gov.uk/government/statistics/chapters-for-english-housing-survey-2023-to-2024-headline-findings-on-demographics-and-household-resilience/chapter-1-profile-of-households-and-dwellings): 65% of households own; by age (11%, 42%, 64%, 74%, 79% from 18-24 to 65 and over) and income fifth (factors 0.65 to 1.2) *estimates* shaped like its tables |
| Renters | 35.0% | 37.5% | The rest |
| Drinkers | 49.0% | 33.9% | Health Survey for England: about 46% of 18 to 24 year olds drank in the last week (*secondary*); the other ages, the income factors and the total of 49% are *estimates* |
| Smokers | 10.6% | 34.8% | ONS, Adult smoking habits in the UK 2024: 10.6% of adults; 8.1% at 18 to 24, 12.6% at 25 to 34, 7.1% at 65 and over; 35 to 64 (11.5%, 11%) and the income factors (1.6 to 0.6: routine and manual workers smoke three times as often as managers and professionals) are *estimates* |

A reaction reaches a voter type in proportion to its share in the group, so where a type is
part owner and part renter, reactions of owners and renters to the same policy partly cancel
within it: rent controls raise renters' approval by 0.4 points but leave owners' almost where
it was, since many owners share voter types with renters who gain more. Groups by voter type
cannot be sharper than the types.

## Reactions

Each policy's reaction (`standing_<policy>`, by voter type, summed in `policy_standing`) is
what voters think of it for itself, apart from its effects, which reach them anyway through
incomes, prices, jobs and the issues. All the sizes, listed with each policy above, are
judgements, set so that a policy at an end of its range moves its groups' approval by a point
or two and the national rating by tenths of a point. They are in force while the policy is,
without fading.

## Cost

The policies are national formulas and a few dimensioned by voter type (the reactions); no
new per-household value. The UK month in the engine took 16.4 to 18.2 ms before and 16.1 to
16.5 ms after, within the run-to-run noise (`polisim run models/uk/scenarios/2025.toml --steps 24
--time`, four runs each).
