# Mods

Stage S7.1. A mod changes a model without editing its files: it adds elements and
patches existing ones. The engine (`crates/core/src/model.rs`) loads mods and is held to
the shared cases in `conformance/mod_cases.toml`, each with its recorded outcome and model
hash. A guide with a worked example is
in [`docs/MODDING.md`](../MODDING.md).

Related: [model format 0](01-model-format-v0.md), [model format 1](06-model-format-1.md),
[save formats](04-save-format-v0.md), [the game client](05-game-client.md).

## A mod is a folder

```text
mods/wealth_tax/
  mod.toml
  wealth_tax.toml
```

`mod.toml` holds one table, `[mod]`, and nothing else:

| Key | Meaning |
|---|---|
| `id` | The mod's name: lower-case letters, digits and underscores, starting with a letter and not ending with an underscore. Every name the mod adds starts with it and an underscore |
| `name`, `version`, `description` | Text for the player (the start screen); `name` defaults to the id |
| `model` | Optional: the id of the model (`[model] id`) the mod is for. Loading it into another is an error |
| `files` | The mod's files, in the model format, relative to its folder, read in this order |

## What a mod's files hold

The sections a model file may hold, except that a mod may add only to `[dim]`, `[param]`,
`[lever]`, `[var]`, `[state]`, `[flow]`, `[account]`, `[renamed]`, `[situation]`,
`[dilemma]` (stage S9.1: a dilemma's answers may change the model's own formulas, as
patches do, but only while chosen), `[lag]` (stage S10.5; `mods/year_on_year` is an
example) and `[table]` (stage S11.1, so that a mod may bring its own curves), plus one of
its own, `[patch]`:

- **Adding.** Each element (and each dimension, and each old name in `[renamed]`) is named
  after the mod: `wealth_tax_rate` in the mod `wealth_tax`. A name declared twice, by the
  model or a mod, is an error. Mods cannot bring data files yet: an added element with
  `data`, or with an `initial` read from data, is an error.
- **Patching.** `[patch.<kind>.<name>]`, where the kind is `param`, `lever`, `var`, `state`,
  `flow` or `account`, changes an element that exists by the time the mod is applied (the
  model's, an earlier mod's, or this mod's): each key given replaces the element's key of
  that name, or is added. In a text value, `{base}` stands for the value being replaced:
  in `expr` and `next` it is put in brackets, so `expr = "{base} + wealth_tax_paid"` adds
  to the formula whatever it was; in other keys (a `label`, a `doc`) it is put in as it
  is. `{base}` in a key the element does not have is an error, as is a patch with `data`.

After the mods are applied the model is checked as a whole, exactly as if it had been
written that way: a patch that breaks a formula is an error with the formula as patched.

## Order

The model's own files are read and merged first. Then each mod in the order given: its
`mod.toml`, its files in order (their additions merged as they are read), then its
patches in the order written. A later mod's patch of the same element is applied to the
earlier mod's result; the loader keeps a note of each element two mods patch
(`mod_notes`), which the client shows when a game starts.

## The model hash

The model hash covers the mods: after the model's own files, each mod's `mod.toml` and
then each of its files, in the order above, each preceded by its name, `mod:<id>/mod.toml`
or `mod:<id>/<file>` (the file's path relative to the mod, with `/` between parts), as the
model's own files are. So a save knows its mods: a game saved with a mod and loaded without
it is a changed model, and migration (save format 1) drops the mod's values and carries the
rest.

## Where mods come from

- **A scenario** lists mods in `[scenario] mods = ["../../../mods/wealth_tax"]`, folders
  relative to the scenario file, applied in order.
- **The player** picks mods on the client's start screen from the game's `mods` folder and
  their own (`user://mods`), shown when the mod is for the scenario's model or names none.
  These come after the scenario's own. A saved game records the folders of the mods the
  player chose (session save version 3), and loading it finds them again; a mod that is no
  longer there is left out, and the player is told.
- **Hot reload** reads the mods again with the model.

## Not yet

Data files in mods; mods that add entities, streams or tables, sectors or instruments; a
mod removing an element; dependencies between mods; text for translations (stage S7.4).
