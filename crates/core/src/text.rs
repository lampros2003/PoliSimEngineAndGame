//! Stage S7.4: text kept apart from the model, so that a game can be played in another
//! language. A model folder (and a mod's) may hold `text/<language>.toml`:
//!
//! ```toml
//! [text]
//! language = "fr"
//! name = "Français"
//!
//! [element.basic_rate]
//! label = "Taux de base"
//! doc = "Taux de l'impôt sur le revenu entre l'abattement et le seuil supérieur"
//!
//! [dim.region]
//! labels = ["Nord", "Sud"]
//!
//! [sector.households]
//! label = "Ménages"
//!
//! [play]
//! country = "Valmora"
//! currency_name = "couronnes"
//!
//! [scenario.term]
//! title = "Valmora (un pays d'essai)"
//! summary = "…"
//!
//! [dilemma.strike]          # stage S9.1: a dilemma and its answers
//! label = "Grève des dockers"
//! doc = "…"
//! option.settle = { label = "Accorder la hausse", doc = "…" }
//! ```
//!
//! Text is not part of the run: it is outside the model hash, and the oracle never reads
//! it. What a text file leaves out keeps the model's own words.

use std::path::{Path, PathBuf};

use toml::{Table as Toml, Value};

use crate::describe::Catalogue;
use crate::error::{Error, Result, model_err};
use crate::model::Model;

/// A language's text for a model and its mods, merged.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Text {
    /// The language's code, as in the file names: `fr`.
    pub language: String,
    /// Its name in itself: `Français`.
    pub name: String,
    pub table: Toml,
}

/// The folders whose `text/` a model reads: its own, then each mod's.
fn folders(model: &Model) -> Vec<PathBuf> {
    let mut out = vec![model.root.join("text")];
    out.extend(model.mods.iter().map(|m| m.dir.join("text")));
    out
}

fn read(file: &Path) -> Result<Toml> {
    let text =
        std::fs::read_to_string(file).map_err(|e| Error::Model(format!("cannot read {}: {e}", file.display())))?;
    text.parse::<Toml>().map_err(|e| Error::Model(format!("{}: {e}", file.display())))
}

/// The languages a model's text folders offer, as (code, name), sorted by code.
pub fn languages(model: &Model) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = Vec::new();
    for folder in folders(model) {
        for entry in std::fs::read_dir(folder).into_iter().flatten().flatten() {
            let path = entry.path();
            if path.extension().is_none_or(|e| e != "toml") {
                continue;
            }
            let Some(code) = path.file_stem().map(|s| s.to_string_lossy().into_owned()) else { continue };
            if out.iter().any(|(c, _)| *c == code) {
                continue;
            }
            let name = read(&path)
                .ok()
                .and_then(|t| t.get("text").and_then(|h| h.get("name")).and_then(Value::as_str).map(str::to_string))
                .unwrap_or_else(|| code.clone());
            out.push((code, name));
        }
    }
    out.sort();
    out
}

/// A language's text: the model's file, then each mod's, a later file's keys replacing an
/// earlier's. `None` when no folder has the language.
pub fn load_text(model: &Model, language: &str) -> Result<Option<Text>> {
    let mut found = false;
    let mut out = Text { language: language.to_string(), name: language.to_string(), table: Toml::new() };
    for folder in folders(model) {
        let file = folder.join(format!("{language}.toml"));
        if !file.is_file() {
            continue;
        }
        found = true;
        let table = read(&file)?;
        for (section, content) in table {
            let Value::Table(content) = content else {
                return model_err(format!("{}: [{section}] must be a table", file.display()));
            };
            if !["text", "element", "dim", "sector", "play", "scenario", "dilemma"].contains(&section.as_str()) {
                return model_err(format!("{}: unknown section [{section}]", file.display()));
            }
            merge(out.table.entry(section).or_insert_with(|| Value::Table(Toml::new())), content);
        }
    }
    if let Some(name) = out.table.get("text").and_then(|h| h.get("name")).and_then(Value::as_str) {
        out.name = name.to_string();
    }
    Ok(found.then_some(out))
}

/// Merges `from` into `into`, table by table; other values replace.
fn merge(into: &mut Value, from: Toml) {
    let Value::Table(into) = into else { return };
    for (key, value) in from {
        match (into.get_mut(&key), value) {
            (Some(existing @ Value::Table(_)), Value::Table(more)) => merge(existing, more),
            (_, value) => {
                into.insert(key, value);
            }
        }
    }
}

impl Text {
    fn get(&self, section: &str, name: &str, key: &str) -> Option<&Value> {
        self.table.get(section)?.get(name)?.get(key)
    }

    fn text(&self, section: &str, name: &str, key: &str) -> Option<String> {
        self.get(section, name, key).and_then(Value::as_str).map(str::to_string)
    }

    /// Replaces the catalogue's words with this text's, where it has them.
    pub fn apply(&self, catalogue: &mut Catalogue) {
        for entry in &mut catalogue.entries {
            if let Some(label) = self.text("element", &entry.name, "label") {
                entry.label = label;
            }
            if let Some(doc) = self.text("element", &entry.name, "doc") {
                entry.doc = doc;
            }
        }
        for sector in &mut catalogue.sectors {
            if let Some(label) = self.text("sector", &sector.name, "label") {
                sector.label = label;
            }
        }
        for dilemma in &mut catalogue.dilemmas {
            let words = self.table.get("dilemma").and_then(|d| d.get(&dilemma.name));
            let word = |table: Option<&Value>, key: &str| {
                table.and_then(|t| t.get(key)).and_then(Value::as_str).map(str::to_string)
            };
            if let Some(label) = word(words, "label") {
                dilemma.label = label.clone();
                // The dilemma's lever carries its words too.
                if let Some(entry) = catalogue.entries.iter_mut().find(|e| e.name == dilemma.name) {
                    entry.label = label;
                }
            }
            if let Some(doc) = word(words, "doc") {
                dilemma.doc = doc;
            }
            for option in &mut dilemma.options {
                let answer = words.and_then(|w| w.get("option")).and_then(|o| o.get(&option.name));
                if let Some(label) = word(answer, "label") {
                    option.label = label;
                }
                if let Some(doc) = word(answer, "doc") {
                    option.doc = doc;
                }
            }
        }
        for dim in &mut catalogue.dims {
            if let Some(Value::Array(labels)) = self.get("dim", &dim.name, "labels") {
                let labels: Vec<String> = labels.iter().filter_map(Value::as_str).map(str::to_string).collect();
                if labels.len() == dim.labels.len() {
                    dim.labels = labels;
                }
            }
        }
    }

    /// Replaces a scenario's `[play]` words with this text's: `[play]` for every scenario
    /// of the model, `[scenario.<file name>]` for one.
    pub fn apply_play(&self, play: &mut Toml, scenario: &str) {
        for source in [self.table.get("play"), self.table.get("scenario").and_then(|s| s.get(scenario))] {
            if let Some(Value::Table(words)) = source {
                for (key, value) in words {
                    play.insert(key.clone(), value.clone());
                }
            }
        }
    }

    /// What the model has words for that this text does not translate, as
    /// `element.<name>.label` and the like, in model order.
    pub fn missing(&self, model: &Model) -> Vec<String> {
        let mut out = Vec::new();
        for d in &model.symbols {
            // A dilemma's elements take its words, which are checked below.
            if d.spec.contains_key("dilemma") {
                continue;
            }
            for key in ["label", "doc"] {
                if d.spec.contains_key(key) && self.text("element", &d.name, key).is_none() {
                    out.push(format!("element.{}.{key}", d.name));
                }
            }
        }
        for dim in &model.dims {
            let has_labels = dim.labels.iter().zip(&dim.members).any(|(l, m)| l != m);
            let translated =
                matches!(self.get("dim", &dim.name, "labels"), Some(Value::Array(l)) if l.len() == dim.labels.len());
            if has_labels && !translated {
                out.push(format!("dim.{}.labels", dim.name));
            }
        }
        for dilemma in &model.dilemmas {
            let words = self.table.get("dilemma").and_then(|d| d.get(&dilemma.name));
            let has =
                |table: Option<&Value>, key: &str| table.and_then(|t| t.get(key)).and_then(Value::as_str).is_some();
            let lever = model.sym(&dilemma.name);
            for key in ["label", "doc"] {
                if lever.is_some_and(|d| d.spec.contains_key(key)) && !has(words, key) {
                    out.push(format!("dilemma.{}.{key}", dilemma.name));
                }
            }
            for option in &dilemma.options {
                let answer = words.and_then(|w| w.get("option")).and_then(|o| o.get(&option.name));
                if option.label != option.name && !has(answer, "label") {
                    out.push(format!("dilemma.{}.option.{}.label", dilemma.name, option.name));
                }
                if !option.doc.is_empty() && !has(answer, "doc") {
                    out.push(format!("dilemma.{}.option.{}.doc", dilemma.name, option.name));
                }
            }
        }
        // The catalogue names sectors after themselves, so every one wants a translation.
        for sector in &model.sectors {
            if self.text("sector", &sector.name, "label").is_none() {
                out.push(format!("sector.{}.label", sector.name));
            }
        }
        out
    }
}
