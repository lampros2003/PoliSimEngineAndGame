//! Stage S10: what comes from outside must be refused, never crash the engine. Saved games
//! cut short or with bytes changed, and model files with text changed, are loaded many
//! times; every attempt must return (an error, or a model or game that works), not panic.

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::PathBuf;
use std::sync::Arc;

use polisim_core::{Simulation, load_model, load_scenario};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// A small fixed generator (xorshift), so every run tries the same mutations.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n.max(1) as u64) as usize
    }
}

#[test]
fn damaged_saves_are_refused_or_load_without_panicking() {
    let scenario = load_scenario(&root().join("models/toy/scenarios/baseline.toml")).unwrap();
    let model = Arc::new(scenario.model.clone());
    let mut sim = Simulation::new(Arc::clone(&model), scenario.config()).unwrap();
    for _ in 0..3 {
        sim.step().unwrap();
    }
    let good = sim.save();
    let mut rng = Rng(0x5eed_1234_abcd_9876);
    let mut panics = Vec::new();
    for trial in 0..3000 {
        let mut bytes = good.clone();
        match trial % 3 {
            0 => bytes.truncate(rng.below(good.len())),
            1 => {
                for _ in 0..1 + rng.below(4) {
                    let at = rng.below(bytes.len());
                    bytes[at] = rng.next() as u8;
                }
            }
            _ => {
                let at = rng.below(bytes.len());
                let len = rng.below(16).min(bytes.len() - at);
                bytes.drain(at..at + len);
            }
        }
        let outcome = catch_unwind(AssertUnwindSafe(|| {
            if let Ok(mut resumed) = Simulation::resume(Arc::clone(&model), &bytes) {
                let _ = resumed.step();
            }
        }));
        if outcome.is_err() {
            panics.push(trial);
        }
    }
    assert!(panics.is_empty(), "damaged saves made the engine panic in trials {panics:?}");
}

/// Small edits to a model's text: a line dropped or repeated, a character dropped,
/// changed or repeated, a number changed, two lines swapped.
fn mutate(text: &str, rng: &mut Rng) -> String {
    let mut lines: Vec<String> = text.lines().map(str::to_string).collect();
    match rng.below(6) {
        0 => {
            let at = rng.below(lines.len());
            lines.remove(at);
        }
        1 => {
            let at = rng.below(lines.len());
            let line = lines[at].clone();
            lines.insert(at, line);
        }
        2 => {
            let (a, b) = (rng.below(lines.len()), rng.below(lines.len()));
            lines.swap(a, b);
        }
        kind => {
            let at = rng.below(lines.len());
            let mut chars: Vec<char> = lines[at].chars().collect();
            if !chars.is_empty() {
                let i = rng.below(chars.len());
                let pool = ['0', '9', '-', '.', '"', '[', ']', '(', ')', '=', ',', '*', '/', 'x', ' ', 'e'];
                match kind {
                    3 => {
                        chars.remove(i);
                    }
                    4 => chars[i] = pool[rng.below(pool.len())],
                    _ => chars.insert(i, chars[i]),
                }
            }
            lines[at] = chars.into_iter().collect();
        }
    }
    lines.join("\n") + "\n"
}

fn fuzz_model(folder: &str, trials: usize, steps: usize, seed: u64) -> Vec<String> {
    let source = root().join(folder);
    let files: Vec<PathBuf> = std::fs::read_dir(&source)
        .unwrap()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e == "toml"))
        .collect();
    let dir = std::env::temp_dir().join(format!("polisim-fuzz-{}-{seed}", std::process::id()));
    let mut rng = Rng(seed);
    let mut panics = Vec::new();
    for trial in 0..trials {
        let _ = std::fs::remove_dir_all(&dir);
        copy_tree(&source, &dir);
        let file = &files[rng.below(files.len())];
        let text = std::fs::read_to_string(file).unwrap();
        let mut changed = mutate(&text, &mut rng);
        if rng.below(2) == 0 {
            changed = mutate(&changed, &mut rng);
        }
        let target = dir.join(file.file_name().unwrap());
        std::fs::write(&target, &changed).unwrap();
        let outcome = catch_unwind(AssertUnwindSafe(|| {
            if let Ok(model) = load_model(&dir) {
                let model = Arc::new(model);
                if let Ok(mut sim) = Simulation::new(model, polisim_core::RunConfig::default()) {
                    for _ in 0..steps {
                        if sim.step().is_err() {
                            break;
                        }
                    }
                }
            }
        }));
        if outcome.is_err() {
            panics.push(format!("trial {trial}, {}", file.file_name().unwrap().to_string_lossy()));
        }
    }
    let _ = std::fs::remove_dir_all(&dir);
    panics
}

fn copy_tree(from: &std::path::Path, to: &std::path::Path) {
    std::fs::create_dir_all(to).unwrap();
    for entry in std::fs::read_dir(from).unwrap().flatten() {
        let path = entry.path();
        if path.is_dir() {
            copy_tree(&path, &to.join(entry.file_name()));
        } else {
            std::fs::copy(&path, to.join(entry.file_name())).unwrap();
        }
    }
}

#[test]
fn damaged_model_files_are_refused_or_run_without_panicking() {
    let mut panics = fuzz_model("models/toy", 600, 3, 0x0ddb_a11c_0ffe);
    panics.extend(fuzz_model("models/cohort", 300, 2, 0xfeed_beef_1357));
    assert!(panics.is_empty(), "damaged model files made the engine panic: {panics:?}");
}

#[test]
fn damaged_dilemmas_and_situations_are_refused_or_run_without_panicking() {
    // The shared dilemma cases' base, with situations and dilemmas whose answers change
    // formulas, as the source to damage.
    let cases: toml::Table =
        std::fs::read_to_string(root().join("conformance/dilemma_cases.toml")).unwrap().parse().unwrap();
    let base = cases["base"].as_str().unwrap();
    let extra = r#"
[situation.busy]
label = "Busy"
start = "count >= 2"
end = "count >= 4"

[dilemma.d]
label = "D"
start = "count >= 1"
again_after = 2

[[dilemma.d.option]]
name = "a"
months = 2
effect = { cost = "{base} + 1.0", stock = "{base} * 2" }

[[dilemma.d.option]]
name = "b"
effect = { cost = "{base} - 1.0" }

[dilemma.e]
start = "busy"

[[dilemma.e.option]]
name = "a"
effect = { cost = "{base} * 3.0" }

[[dilemma.e.option]]
name = "b"
"#;
    let source = std::env::temp_dir().join(format!("polisim-fuzz-source-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&source);
    std::fs::create_dir_all(&source).unwrap();
    std::fs::write(source.join("model.toml"), format!("{base}\n{extra}")).unwrap();
    load_model(&source).expect("the undamaged source loads");
    let relative = source.strip_prefix(root()).map(|p| p.to_path_buf()).unwrap_or(source.clone());
    let panics = fuzz_model(relative.to_str().unwrap(), 1500, 4, 0xd11e_77a5);
    let _ = std::fs::remove_dir_all(&source);
    assert!(panics.is_empty(), "damaged dilemmas made the engine panic: {panics:?}");
}

#[test]
fn damaged_uk_files_are_refused_or_run_without_panicking() {
    let panics = fuzz_model("models/uk", 40, 1, 0x0b5e_55ed_0001);
    assert!(panics.is_empty(), "damaged UK files made the engine panic: {panics:?}");
}
