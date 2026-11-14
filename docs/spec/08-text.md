# Text apart from the model

Stage S7.4. A model's words (labels, help text, the names of dimension members and
sectors, a scenario's title) are in its own files, in one language. A translation is a
file of the same words in another, kept apart from the model so that it never changes a
run: text is outside the model hash and the oracle never reads it. The engine reads it
(`crates/core/src/text.rs`) for a game client.

Related: [model format 0](01-model-format-v0.md), [mods](07-mods.md),
[the game client](05-game-client.md).

## Where text lives

`text/<language>.toml` in a model's folder, and in a mod's. The language is a code, such
as `fr`, the file's name. For a language, the model's file is read first, then each mod's
in the mods' order, a later file's words replacing an earlier's. So a translation can be a
mod with nothing but a `text` folder (its `mod.toml` naming no files), and a mod that adds
elements can bring their words in several languages.

## What a text file holds

```toml
[text]
language = "fr"
name = "Français"          # the language's name in itself, for a menu

[element.basic_rate]       # any element: label and doc
label = "Taux de base de l'impôt sur le revenu"
doc = "Taux de l'impôt sur le revenu entre l'abattement et le seuil supérieur"

[dim.region]               # a dimension's member labels, all of them, in order
labels = ["Nord", "Sud"]

[sector.households]
label = "Ménages"

[play]                     # words in every scenario's [play] table
currency_name = "couronnes"

[scenario.term]            # one scenario's, by its file name
title = "Valmora (un pays d'essai)"
summary = "…"

[dilemma.dock_strike_walkout]   # stage S9.1: a dilemma, and its answers by name
label = "Grève des dockers"
doc = "…"
option.settle = { label = "Payer les dockers", doc = "…" }
```

Any other section is an error. Words the file does not give keep the model's own. A
dimension's labels are used only when the file gives one for every member.

## Checking a translation

```bash
polisim text models/valmora/scenarios/term.toml fr
```

lists what the model has words for that the language does not translate (each element's
`label` and `doc`, each dimension with labels of its own, each sector, and each dilemma's
`label` and `doc` and its answers' own labels and docs, as `dilemma.<name>.option.<answer>.label`;
the elements a dilemma makes take its words), one key a line
such as `element.basic_rate.doc`, and exits with 1 if there is anything. Without a
language it lists the languages the scenario's model and mods have text in.

## In a game

A session's language (`Session::set_language`) rebuilds its catalogue and its scenario's
`[play]` table in that language, or in the model's own words with `""`; a language the
model has no text in is refused. The run does not change: the same state hashes in any
language. Hot reload reads the text again; a game loaded in the client keeps the language
it was opened in.

The client offers each language the chosen scenario's model has text in on its start
screen (`--language=CODE` opens one directly). The client's own words (its buttons and
headings) are English for now.
