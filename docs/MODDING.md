# Making a mod

A mod adds to a country's model, or changes it, without editing the model's files: a new
tax, a new policy, a different view of how voters react. This guide builds the example
that ships with the game, `mods/dog_licence`, a dog licence for the United Kingdom (Great
Britain had one until the late 1980s; Northern Ireland still has). The
precise rules are in [`docs/spec/07-mods.md`](spec/07-mods.md); the model format they
build on is in [`docs/spec/01-model-format-v0.md`](spec/01-model-format-v0.md) and
[`docs/spec/06-model-format-1.md`](spec/06-model-format-1.md).

Until stage S17 the example was a wealth tax. Since stage S15 the UK has had a wealth tax of
its own (`net_wealth_tax`, on the Add policy sheet under Tax), so the start screen was
offering a mod that doubled a policy already in the game. That mod is kept for the engine's
tests (`tests/mods/wealth_tax`) and no longer ships; the example here adds something the
model lacks.

## 1. A folder and a mod.toml

Make a folder for the mod. To play it, put it in your own mods folder (the start screen
shows where: on Windows, under `%APPDATA%\Godot\app_userdata\PoliSim\mods`), or in the
game's `mods` folder. In it, `mod.toml` says what the mod is:

```toml
[mod]
id = "dog_licence"
name = "A dog licence"
version = "1.0"
model = "uk"
description = "A yearly licence for every dog, paid to the government, as Great Britain had until the late 1980s and Northern Ireland still has. Dog owners hold it against the government."
files = ["dog_licence.toml"]
```

`model = "uk"` means the start screen offers the mod only for the United Kingdom.

## 2. Add what is new

The mod's own file, `dog_licence.toml`, is written like any model file. Every name you add
starts with your mod's id, so that mods never collide.

A **lever** the player sets, which stands on the board as a policy in an area named after
its group (an area of that name if the scenario has one, else a new one at the end of the
rim). A mod cannot place nodes on the board otherwise: where indicators and groups stand,
their colours, which statistic a situation belongs to, the search's extra words and
Parliament's stances are the scenario's `[play.web]` table
([`docs/spec/05-game-client.md`](spec/05-game-client.md)). A mod's lever is a policy in
force, never one on the Add policy sheet: the sheet offers only the scenario's policies with
an `off` setting. `type = "money"` makes it an amount in pounds and pence;
`leaning = "left"`
makes raising it a bill the House of Commons votes on, as a move to the left:

```toml
[lever.dog_licence_fee]
label = "Dog licence"
group = "Dog licence"
type = "money"
unit = "GBP/licence"
default = 0.0
range = [0, 200]
leaning = "left"
doc = "What a year's licence for one dog costs. Nought: no licence is needed"
```

**Parameters** for your judgements, with a `doc` that says where the number comes from:

```toml
[param.dog_licence_bought]
doc = "Licences bought a month: one a year for each of about ten million dogs (a round figure and a judgement)"
type = "real"
unit = "licence/month"
value = 833333.33
```

A **flow**: money moving from one sector to another each month. It appears on the Budget
sheet by itself, because the budget is built from the flows into and out of the
government:

```toml
[flow.dog_licence_paid]
label = "Dog licences"
from = "households"
to = "government"
phase = "spending"
expr = "round(dog_licence_fee * dog_licence_bought)"
```

Units are checked: pounds a licence times licences a month is pounds a month, as a flow
must be. A mistake shows when the game starts, with the formula.

## 3. Patch what the model already does

A fee that only moved money would not count in the budget balance, which the UK model
computes from its list of receipts, and no voter would mind it. `[patch]` changes the
model's own elements, and `{base}` stands for what was there, so you add to a formula
without copying it:

```toml
[patch.var.public_receipts]
expr = "{base} + dog_licence_paid"

[patch.var.voter_fundamentals]
expr = "{base} - dog_licence_aversion * dog_licence_owners * dog_licence_fee / dog_licence_dear"
```

The second patch takes a little from every voter's regard for the government: three more
parameters say what share of voters live with a dog (three in ten), what fee an owner would
call dear (£100) and how much a dear fee weighs with one. The mod does not know which
voters own dogs, so every type of voter is taken to hold the average share of them. A mod
can single voters out: the UK's 600 voter types run by region, age band, income quintile
and in work or not, the last fastest, so a value with `dims = ["voter_type"]` can work out
a type's quintile from its position, as the wealth tax kept in `tests/mods/wealth_tax`
does to find the richest fifth:

```toml
[var.wealth_tax_richest]
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type"]
expr = "select(floor(coord(voter_type) / 2.0) - 5.0 * floor(coord(voter_type) / 10.0) == 4.0, 1.0, 0.0)"
```

To find what to patch, use the game itself: click an indicator, and **Why it moved last
month** lists what it is made of. The model's files are in
`game/models/uk/`; `politics.toml` holds the voters.

## 4. Try it

Start the game, tick the mod on the start screen and choose New game. The title bar names
the mods in play. Open the Dog licence policy (its area is at the end of the rim), set the fee to £50 and
advance a month: the Budget shows
about £500m a year of dog licences, and after a year the government's poll rating is about
a sixth of a point lower than it would have been (two thirds of a point at £200).
`models/uk/scenarios/dog_licence.toml` runs the same from the command line.

While playing, edit the mod's file and press **Reload model**: the mod is read again with
the model, and the change takes effect from the next month.

A saved game remembers its mods. If you load it after removing a mod, it carries on
without the mod's values and says so.

## A dilemma

A mod can put a question to the player: `mods/dock_strike` is one, for Valmora. Its file
declares a counter of months and a dilemma that opens in the third:

```toml
[dilemma.dock_strike_walkout]
label = "Dock strike"
doc = "Valmora's dockers have walked out over pay. While the ports are shut, firms lose sales"
start = "dock_strike_month >= 2"

[[dilemma.dock_strike_walkout.option]]
name = "settle"
label = "Pay the dockers"
doc = "The government meets the claim: its purchases rise by a fifth for six months"
months = 6
effect = { gov_spending = "round({base} * 1.2)" }

[[dilemma.dock_strike_walkout.option]]
name = "wait"
label = "Wait them out"
doc = "The ports stay shut for three months: firms' sales fall by a tenth"
months = 3
effect = { net_sales = "round({base} * 0.9)" }
```

`start` is when the question is put; each answer's `effect` changes formulas the model
already has, with `{base}` for the formula as it was, for `months` months from the answer
(or for good without `months`); `again_after = 24` would put the question again two years
after an answer, if `start` still holds. The game stops and asks when the dilemma opens,
and the answer shows as a pennant on the strip under the top bar while it lasts. Everything
a dilemma does is an ordinary formula, so **Why it moved last month** in government
purchases' popup shows the strike's effect. The format, with every
rule, is in [`docs/spec/06-model-format-1.md`](spec/06-model-format-1.md#dilemmas-stage-s91);
`models/valmora/scenarios/dock_strike.toml` opens Valmora with the mod.

## Values from months back, and growth rates

`prev(x)` gives a value as it was last month. For longer, a mod declares a lag:
`mods/year_on_year` follows Valmora's output a year back and works out its growth over the
year.

```toml
[lag.yoy_gdp_a_year_before]
label = "Output a year before"
of = "gdp"
steps = 12
initial = 0

[var.yoy_growth]
label = "Growth over the year"
type = "real"
unit = "1"
phase = "government"
expr = "select(yoy_gdp_a_year_before > 0, gdp / yoy_gdp_a_year_before - 1.0, 0.0)"
```

The loader turns the lag into twelve states, each passing its value on to the next, and a
value that holds `gdp` as it was twelve months before (`initial` until then); **Why it
moved last month** shows it as output twelve months before. The rules are in
[`docs/spec/06-model-format-1.md`](spec/06-model-format-1.md#lags-stage-s105). For rates
and elasticities, formulas also have `ln`, `sqrt` and `pow` (as `pow(1.0 + rate, 12)`), each
computed the same way on every machine
([`docs/spec/02-formula-language-v0.md`](spec/02-formula-language-v0.md#functions)).

## Words in other languages

A mod may bring its words in other languages: `text/fr.toml` in its folder, as
[`docs/spec/08-text.md`](spec/08-text.md) describes, with `[element.dog_licence_fee]` and
so on. A translation of a whole country is a mod too: a `mod.toml` with no files and a
`text` folder. `polisim text <scenario> <language>` lists what is left untranslated. A
dilemma's words go in `[dilemma.<name>]`, with each answer's under `option.<answer>`, as
`mods/dock_strike/text/fr.toml` shows.

## Limits for now

A mod cannot bring data files, add households or other record sets, add sectors, or remove
an element. Two mods may patch the same formula: the later one is applied to the earlier
one's result, and the game notes it when the game starts.
