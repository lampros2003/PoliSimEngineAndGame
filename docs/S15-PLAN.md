# Stage S15: after the second playtest

## Context

The owner played the S14 game on 2026-11-16 ("better by quite a bit") and asked for:

1. **Regions** on the ring seem needlessly complex and he cannot tell what they do. Perhaps
   they should come back with devolution. Later.
2. **Groups by ideology** (socialist, capitalist and so on), **farmers, rural and urban**,
   and whatever other groups make interesting play.
3. **Adding a policy** is counter-intuitive. One central "Add policy" menu, by category,
   instead of the "New policy" bubbles.
4. **Statistics**: which important or interesting ones are missing, and which are on the
   board without making sense or being used.
5. **A search bar** for policies and statistics. He saw "strong growth" happen and could not
   find it on the board.

## Decisions

### Groups

A group is worth its place on the ring when some policy pleases it and angers another.
The ring is rebuilt round those quarrels.

| Family | Groups | The quarrel |
|---|---|---|
| Beliefs (new) | Socialists, Capitalists, Liberals, Conservatives, Environmentalists, Patriots | Tax and spend; liberty and order; green against cheap; the nation against the world |
| Work | In work, Out of work, The self-employed, Public sector workers (new), Trade unionists (new), Farmers (new) | Public pay and strikes; benefits; farm support and trade |
| Homes and places | Home owners, Renters, Town and city (new), Countryside (new) | Planning, rents, mortgages; buses against fuel duty |
| Ages | The young, Mid-life, Pensioners | As now |
| Incomes | Low, Middle, High | As now |
| Families | Parents, Lone parents | As now |
| Ways of life | Motorists, Drinkers | Smokers leave the ring: tobacco duty has no other side to it |

| Question | Decision |
|---|---|
| The seven regions | Off the ring. They stay in the model and in Parliament's table by place, and come back when devolution gives them something to do (a later stage) |
| Who is in a belief group | Shares by voter type (age, income, work, region) from published surveys (British Social Attitudes, the British Election Study), as the estimated groups already are. A voter can be in several |
| What moves a belief group | Where the government stands, not how the voter is doing. Four stances are worked out from the settings of the policies against their 2024 settings: the state against the market, liberty against order, green, and the nation. Socialists and Capitalists read the first, Liberals and Conservatives the second, Environmentalists the third, Patriots the fourth. Every policy is tagged for the stances it moves. The reactions reach real votes through the voter types, by membership |
| Where a player sees it | A group's popup lists the policies that matter most to it, as now. Parliament shows the four stances as four small scales |
| Sizes | Judgements, documented, tuned so a clear move on a stance shifts its groups by two to five points and the country by under one |

### Policies to add

The menu needs things worth adding, and the new groups need something to fight over. About
ten more policies that start not in force, each neutral until introduced, each with its
money through the accounts and reactions among the groups: among them a wealth tax, farm
support, public ownership of rail, congestion charging in cities, research grants, support
for onshore wind, free childcare hours, help with energy bills, identity cards, and limits
on strikes. Trade union law and public sector pay policy join as policies in force.

### Statistics

A statistic earns its place when a policy the player holds moves it and it moves a group, a
situation or another statistic. An audit measures that for each one (how many policies move
it by a noticeable amount in a year, and what it feeds).

| | Statistics | Why |
|---|---|---|
| Add | Inequality (Gini, from the household records); Tax burden (receipts as a share of output); Rents; House prices; Energy bills; Days lost to strikes; Business confidence; Farm incomes; Congestion; Air pollution; Research and development; Trade balance | Each is what one of the new groups or policies is about, or closes a loop that ended nowhere |
| Leave the board (stay in the model and the popups) | Tax receipts (the Budget has it); Imports and Exports (the trade balance replaces them); Housing stock (homes built says it); NHS treatments (a step toward the waiting list); Jobs (unemployment says it); Household income (median income says it); Working-age poverty (poverty, child and pensioner poverty stay); Homes' emissions (part of emissions) | Doubles of another node, or steps on the way to one |
| Unless the audit says otherwise | Anything no policy moves and that feeds nothing leaves the board; anything the list above removes that turns out to be the only way a policy shows stays | The audit decides the edge cases, and is reported |

### The interface

| Question | Decision |
|---|---|
| Adding a policy | "Add policy" on the top bar (and the key A) opens one sheet: the areas down the side, each area's policies not in force with a line on what it does, the smallest step's cost in capital, and who would cheer and who would boo. Choosing one opens its popup to set it and put it to the Commons. The "New policy" bubbles leave the board |
| Search | A field on the top bar ("/" or Ctrl+F): typing dims the board to the nodes that match, by name and by other words for them (the scenario may give `also = ["growth", "boom"]`); it finds policies, statistics, groups, situations and policies not in force; Enter opens the first, the arrows move between matches, Esc clears |
| Finding a situation | A situation belongs to the statistic that sets it off. Its pennant on the strip, its line in the report and a search for its name all light that node, and the node wears a small flag while the situation lasts. The model says which statistic (the row its condition reads) |
| The ring | Seven families. Names at rest stay all-or-none |

## Stages

| # | Stage | Lane | Done when |
|---|---|---|---|
| S15.1 | **The interface**: the Add policy sheet, search, situations tied to their nodes | Client, in the checkout | Scripted checks for each (introduce through the sheet; search finds "strong growth" and lights the Growth node; a pennant lights its node); no "New policy" node on the board |
| S15.2 | **Groups, policies, statistics** in the UK model | Model, in a private copy | The base month and the hindcast unchanged; tests for every new group, stance, policy and statistic; the audit reported; the nine strategies run again |
| S15.3 | **Joined**: the new ring and the new nodes on the board, labels at three sizes, the guide and spec | Client, after both | Every check passes; screenshots looked at |

## Status

| # | Status |
|---|---|
| S15.1 | Done. **Add policy** on the top bar (key A) opens one sheet (`client/scripts/add_policy.gd`): the areas down the side with how many each has to add, and for the chosen area each policy not in force with what it does, the smallest step's cost in capital, the vote the Commons would give, and the three groups it would raise and lower most (the effects table now also measures policies not in force). Choosing one opens its popup set to its first step. The "New policy" bubbles and `introduce_list.gd` are gone. **Search** (`search.gd`; "/" or Ctrl+F) finds policies, statistics, groups, situations and policies not in force by label, the scenario's optional `also` words, the model's name and its doc, from an index built once (2.4 ms a key); the chosen match's node wears an ochre ring and the rest dims. **Situations** belong to a statistic (`[play.web]` `situations = { name = "row" }`): its node wears a small pennant while the situation lasts, and the strip's pennant, the report's line and a search all light the node and open the situation's own popup with "Set off by". The checks read the scenario's groups, families and areas, and the ring holds thirty groups at 1366x768 by thinning its band (`tests/add_search_check.gd`) |
| S15.2 | Under way |
| S15.3 | Planned |
