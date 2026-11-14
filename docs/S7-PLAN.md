# Stage S7: content and public surface

Written 2026-11-14, after S6. The roadmap's line for this stage: interface depth, mod
documentation, save migration, Workshop, Early Access, a second country, opening the
engine's source. Business decisions (price, store page, timing) arrive here.

## What is the owner's

These are decisions, not work, and nothing in this plan commits to them:

| Decision | What it needs before it can be taken |
|---|---|
| Early Access: whether, when, at what price | A play test by the owner (still open since S2), a store page, a Steam account |
| Steam Workshop | A Steamworks app; the mod format (S7.1) is built so that a mod is one folder, which is what the Workshop carries |
| A second country | Which one, and its data licences checked by the owner; the UK pipeline (`tools/uk/`) is the template |
| Opening the engine's source | The ballot chose closed source; reopening it is the owner's call |
| Real party names | Still open from S5 |

## Decisions

Proposed here, and taken as decided unless the owner changes them.

| Question | Decision | Why |
|---|---|---|
| Order | Saves that survive model changes first, then mods, then the modding guide, then situations, then text kept apart from the model | Every later change to a model breaks saves until migration exists; mods change models by design |
| Save migration | Save format 1 records each persistent value's kind, its entity (name and a hash of its record ids) and its dimensions (names and members). Loading into a changed model carries every value whose name, kind, shape and type still match, the way hot reload already does; a model may declare renames (`[renamed] old = "new"`); a lever outside its new range is clamped to it; parameters come from the new model; anything new starts from its initial value. The player is told what was carried and what started again. Format 0 saves still load into their own model only | Factorio's lesson in the research notes: explicit, declarative migrations with stable identifiers are the only way long-lived saves stay reliable. Hot reload already proves the carrying rules |
| Mods | A mod is a folder with `mod.toml` (id, name, version, description, files). A scenario lists mods in order (`mods = [...]`). A mod adds elements, whose names must start with its id, and patches existing ones key by key (`[patch.<kind>.<name>]`: a new formula, range, default, label). The model hash covers the mods, so saves know them, and migration handles adding or removing one. The oracle and the engine load mods identically | One folder per mod is what the Workshop carries; prefixed names keep mods from colliding; patching by key lets a mod change one formula without copying the model |
| The client and mods | The client lists the mods it finds in the player's mod folder and the game's, and the player picks them before a game starts | The scenario stays the unit of a game |
| Modding guide | `docs/MODDING.md`: the model format as a modder needs it, with a worked example mod for the UK (a wealth tax: a lever, a flow and a patch to the voters), which CI runs on the oracle and the engine | The ballot asked for modding; a guide with a tested example is the cheapest documentation that stays true |
| Situations | `[situation.<name>]` in the model format: a condition (a true/false formula), a label, a sentence, and whether it is good or bad. The client shows the situations in force in a strip under the headline, with the month each began, and announces new ones. The UK model gets a first set (recession, high unemployment, high inflation, debt above its 2024 level, a budget surplus) | The genre's way of telling the player what matters now; the model already computes the conditions |
| Text | Labels, docs and situation sentences may live in `text/<language>.toml` keyed by element name; the model's own labels are the fallback. A translation is a mod that adds text only | The research notes' advice: keys from model identifiers let the validator report missing translations |

## Milestones

| # | Milestone | Done when |
|---|---|---|
| S7.0 | Saves survive model changes | A game saved under the S6.3 UK model loads under the current one and plays on; a test model with a renamed, an added and a removed value migrates as declared; the client tells the player what changed |
| S7.1 | Mods | A scenario with mods loads in the oracle and the engine with the same hash and results; adding and patching are checked at load; the client offers the mods it finds |
| S7.2 | Modding guide and example | `docs/MODDING.md`; the wealth tax mod runs in CI on both sides and in the client |
| S7.3 | Situations | Situations in the format, the oracle and the engine; a strip and announcements in the client; the UK's first set, with a client test that brings one on |
| S7.4 | Text apart from the model | Text files by key, with fallbacks; a check that reports missing keys; a test translation |

## What could go wrong

| Risk | Sign | Response |
|---|---|---|
| A migrated save plays differently from a fresh game in ways players notice | Values carried from an old calibration sit far from the new model's | Say so in the load message; a migrated game is a continued game, not a replay |
| Patches make models impossible to reason about | Two mods patch the same formula | Load order decides, and the loader reports every element patched twice |
| Situations fire too often or never | A five-year run shows a situation flickering on and off | Each situation gets a hysteresis: an end condition as well as a start |

## Status

| # | Status |
|---|---|
| S7.0 | Done. Save format 1 says what each value is (kind, entity and a hash of its record ids, dimensions and members); `Simulation::migrate` loads a save into a changed model by the same rules as hot reload, which now share one function, and reports what it carried, started again, clamped, dropped and renamed. Models declare renames in `[renamed]`, which the oracle checks too (shared cases in `conformance/bill_cases.toml`). A UK game saved after a year under the S6.3 model plays on under the current one: 96 values carried, the two that S6.4 added start fresh (`crates/core/tests/migration.rs`, run by hand with `POLISIM_OLD_UK`). The client tells the player what loading changed (`client/tests/migrate_check.gd`) |
| S7.1 | Done. A mod is a folder with `mod.toml`; its files add elements named after it and patch existing ones key by key, `{base}` standing for what was there (`docs/spec/07-mods.md`). Scenarios list mods (`[scenario] mods`); the oracle and the engine load them identically, with the same model hash (20 shared cases in `conformance/mod_cases.toml`, and the UK with the example mod held to the oracle's hashes). Hot reload reads mods again; a saved game records the mods the player chose (session save version 3) and, if one is gone, carries on without it. The client opens on a start screen: the scenarios with a `[play] title`, the mods for the chosen one's model from the game's `mods` folder and the player's own, New game and Continue (`client/tests/start_screen.gd`). Along the way: customs duties now count as public receipts |
| S7.2 | Done. `docs/MODDING.md` builds the example mod, `mods/wealth_tax`: a wealth tax lever, the tax as a flow and a public receipt, and the richest fifth of voters holding it against the government (a 1% tax raises about £7.6bn a year and costs about a quarter of a point in the polls). CI runs it on the oracle (`oracle/tests/test_mods.py`), the engine (`models/uk/golden/wealth_tax.hashes.csv`) and the client. The Windows build ships the `mods` folder |
| S7.3 | Not started |
| S7.4 | Not started |
