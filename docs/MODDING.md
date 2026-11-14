# Making a mod

A mod adds to a country's model, or changes it, without editing the model's files: a new
tax, a new policy, a different view of how voters react. This guide builds the example
that ships with the game, `mods/wealth_tax`, a wealth tax for the United Kingdom. The
precise rules are in [`docs/spec/07-mods.md`](spec/07-mods.md); the model format they
build on is in [`docs/spec/01-model-format-v0.md`](spec/01-model-format-v0.md) and
[`docs/spec/06-model-format-1.md`](spec/06-model-format-1.md).

## 1. A folder and a mod.toml

Make a folder for the mod. To play it, put it in your own mods folder (the start screen
shows where: on Windows, under `%APPDATA%\Godot\app_userdata\PoliSim\mods`), or in the
game's `mods` folder. In it, `mod.toml` says what the mod is:

```toml
[mod]
id = "wealth_tax"
name = "A wealth tax"
version = "1.0"
model = "uk"
description = "An annual tax on households' savings above a threshold, paid to the government. The richest fifth of voters hold it against the government."
files = ["wealth_tax.toml"]
```

`model = "uk"` means the start screen offers the mod only for the United Kingdom.

## 2. Add what is new

The mod's own file, `wealth_tax.toml`, is written like any model file. Every name you add
starts with your mod's id, so that mods never collide.

A **lever** the player sets, in its own group on the policy panel. `leaning = "left"`
makes raising it a bill the House of Commons votes on, as a move to the left:

```toml
[lever.wealth_tax_rate]
label = "Wealth tax rate"
group = "Wealth tax"
type = "real"
unit = "1"
default = 0.0
range = [0.0, 0.05]
leaning = "left"
doc = "A yearly tax on households' savings above the threshold, as a share of them"
```

**Parameters** for your judgements, with a `doc` that says where the number comes from:

```toml
[param.wealth_tax_share_above]
doc = "The share of households' deposits held above the threshold (a judgement)"
type = "real"
unit = "1"
value = 0.4
```

A **flow**: money moving from one sector to another each month. It appears on the budget
screen by itself, because the budget is built from the flows into and out of the
government:

```toml
[flow.wealth_tax_paid]
label = "Wealth tax"
from = "households"
to = "government"
phase = "spending"
expr = "round(wealth_tax_rate / 12.0 * wealth_tax_share_above * per_step(household_money))"
```

Units are checked: `household_money` is a stock of pounds, and `per_step` turns it into
pounds a month, as a flow must be. A mistake shows when the game starts, with the formula.

## 3. Patch what the model already does

A tax that only moved money would not count in the budget balance, which the UK model
computes from its list of receipts, and no voter would mind it. `[patch]` changes the
model's own elements, and `{base}` stands for what was there, so you add to a formula
without copying it:

```toml
[patch.var.public_receipts]
expr = "{base} + wealth_tax_paid"

[patch.var.voter_fundamentals]
expr = "{base} - wealth_tax_aversion * wealth_tax_rate * wealth_tax_richest"
```

The second patch needs to know which voters are richest. The UK's 600 voter types run by
region, age band, income quintile and in work or not, the last fastest, so a voter type's
quintile can be worked out from its position:

```toml
[var.wealth_tax_richest]
type = "real"
unit = "1"
phase = "politics"
dims = ["voter_type"]
expr = "select(floor(coord(voter_type) / 2.0) - 5.0 * floor(coord(voter_type) / 10.0) == 4.0, 1.0, 0.0)"
```

To find what to patch, use the game itself: **Why** next to any figure lists what it is
made of, and **Connections** shows what depends on it. The model's files are in
`game/models/uk/`; `politics.toml` holds the voters.

## 4. Try it

Start the game, tick the mod on the start screen and choose New game. The title bar names
the mods in play. Set the wealth tax rate to 1% and advance a month: the budget shows
about £7.6bn a year of wealth tax, and the government's poll rating falls by about a
quarter of a point, the richest fifth of voters turning away.

While playing, edit the mod's file and press **Reload model**: the mod is read again with
the model, and the change takes effect from the next month.

A saved game remembers its mods. If you load it after removing a mod, it carries on
without the mod's values and says so.

## Limits for now

A mod cannot bring data files, add households or other record sets, add sectors, or remove
an element. Two mods may patch the same formula: the later one is applied to the earlier
one's result, and the game notes it when the game starts.
