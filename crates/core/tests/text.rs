//! Stage S7.4: text kept apart from the model (models/valmora/text/fr.toml).

use std::path::PathBuf;

use polisim_core::{Catalogue, Session, languages, load_model, load_model_with_mods, load_text};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

#[test]
fn valmora_reads_in_french_with_nothing_left_out() {
    let model = load_model(&root().join("models/valmora")).unwrap();
    assert_eq!(languages(&model), vec![("fr".to_string(), "Français".to_string())]);
    let text = load_text(&model, "fr").unwrap().expect("a French text");
    assert_eq!(text.missing(&model), Vec::<String>::new());
    let mut catalogue = Catalogue::of(&model);
    text.apply(&mut catalogue);
    let label = |name: &str| catalogue.entries.iter().find(|e| e.name == name).unwrap().label.clone();
    assert_eq!(label("basic_rate"), "Taux de base de l'impôt sur le revenu");
    assert_eq!(label("gdp"), "Production (PIB)");
    assert_eq!(catalogue.sectors.iter().find(|s| s.name == "households").unwrap().label, "Ménages");
    assert!(load_text(&model, "de").unwrap().is_none());
}

#[test]
fn a_session_changes_language_without_changing_the_run() {
    let path = root().join("models/valmora/scenarios/term.toml");
    let mut english = Session::open(&path).unwrap();
    let mut french = Session::open(&path).unwrap();
    french.set_language("fr").unwrap();
    assert_eq!(french.language(), "fr");
    assert_eq!(french.catalogue().entry("vat").unwrap().label, "TVA");
    assert_eq!(french.scenario().play["currency_name"].as_str(), Some("couronnes"));
    assert_eq!(french.scenario().play["title"].as_str(), Some("Valmora (un pays d'essai)"));
    for _ in 0..3 {
        english.step().unwrap();
        french.step().unwrap();
    }
    assert_eq!(english.simulation().state_hash(), french.simulation().state_hash());
    // A language the model has no text in is refused, and the session keeps its own.
    assert!(french.set_language("de").is_err());
    assert_eq!(french.language(), "fr");
    french.set_language("").unwrap();
    assert_eq!(french.catalogue().entry("vat").unwrap().label, "VAT");
    assert_eq!(french.scenario().play["currency_name"].as_str(), Some("crowns"));
}

#[test]
fn a_mods_text_comes_after_the_models() {
    let dir = std::env::temp_dir().join(format!("polisim-text-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("text")).unwrap();
    std::fs::write(dir.join("mod.toml"), "[mod]\nid = \"words\"\n").unwrap();
    std::fs::write(dir.join("text/fr.toml"), "[element.vat]\nlabel = \"Taxe sur la valeur ajoutée\"\n").unwrap();
    let model = load_model_with_mods(&root().join("models/valmora"), std::slice::from_ref(&dir)).unwrap();
    // Text is not part of the run: the mod changes the hash only by its mod.toml.
    let text = load_text(&model, "fr").unwrap().unwrap();
    let mut catalogue = Catalogue::of(&model);
    text.apply(&mut catalogue);
    assert_eq!(catalogue.entry("vat").unwrap().label, "Taxe sur la valeur ajoutée");
    assert_eq!(catalogue.entry("gdp").unwrap().label, "Production (PIB)");
    let _ = std::fs::remove_dir_all(dir);
}
