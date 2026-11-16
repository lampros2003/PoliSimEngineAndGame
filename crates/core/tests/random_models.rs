//! Stage S10.7: random whole models (conformance/random_models.toml, written by
//! the Python reference implementation until stage S14.2; now a frozen fixture). On one,
//! two and eight threads, the engine must give the recorded state hash after every step,
//! and stop at the recorded step. They test whole runs: phases and levels, records and their sums, values with
//! dimensions, states, prev, lags, situations, a flow between accounts, random draws and
//! lever commands, together.

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use polisim_core::{RunConfig, Simulation, load_model, pyfmt};
use toml::Value;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// The records of every random model, by the rule of the generator's `records_csv`.
fn records_csv(n: i64) -> String {
    let mut out = String::from("id,weight,ci,cf,cb\n");
    for i in 0..n {
        let v = (i * 7919) % 2001 - 1000;
        let cf = format!("{}{}.{:02}", if v < 0 { "-" } else { "" }, v.abs() / 100, v.abs() % 100);
        let cb = if (i * 13) % 3 == 0 { 1 } else { 0 };
        out += &format!("{i},{},{},{cf},{cb}\n", 1 + (i * 31) % 5, (i * 104729) % 23 - 11);
    }
    out
}

/// The hashes after each step, and the step that failed with its message, if one did.
type Outcome = (Vec<String>, Option<(usize, String)>);

fn run(text: &str, records: i64, config: RunConfig, steps: usize, threads: usize) -> Outcome {
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let n = NEXT.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::temp_dir().join(format!("polisim-random-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("model.toml"), text).unwrap();
    std::fs::write(dir.join("rec.csv"), records_csv(records)).unwrap();
    let model =
        Arc::new(load_model(&dir).unwrap_or_else(|e| panic!("the engine refused a model recorded as running: {e}")));
    let _ = std::fs::remove_dir_all(&dir);
    let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build().unwrap();
    pool.install(|| {
        let mut sim = Simulation::new(model, config).unwrap();
        let mut hashes = Vec::new();
        for step in 0..steps {
            match sim.step() {
                Ok(row) => hashes.push(pyfmt::hex(&row.hash)),
                Err(e) => return (hashes, Some((step, e.to_string()))),
            }
        }
        (hashes, None)
    })
}

#[test]
fn random_models_match_the_recorded_hashes_on_one_two_and_eight_threads() {
    let file: toml::Table =
        std::fs::read_to_string(root().join("conformance/random_models.toml")).unwrap().parse().unwrap();
    let models = file["model"].as_array().unwrap();
    assert!(models.len() >= 80);
    for model in models {
        let model = model.as_table().unwrap();
        let name = model["name"].as_str().unwrap();
        let commands = model["commands"]
            .as_array()
            .unwrap()
            .iter()
            .map(|c| {
                let c = c.as_array().unwrap();
                (c[0].as_integer().unwrap() as u64, c[1].as_str().unwrap().to_string(), c[2].clone())
            })
            .collect();
        let config = RunConfig { seed: model["seed"].as_integer().unwrap() as u64, commands, ..RunConfig::default() };
        let want: Vec<&str> = model["hashes"].as_array().unwrap().iter().map(|h| h.as_str().unwrap()).collect();
        let error = model.get("error_at").and_then(Value::as_integer).map(|s| s as usize);
        let message = model.get("error").and_then(Value::as_str);
        let (text, records) = (model["text"].as_str().unwrap(), model["records"].as_integer().unwrap());
        let steps = model["steps"].as_integer().unwrap() as usize;
        for threads in [1, 2, 8] {
            let (got, failed) = run(text, records, config.clone(), steps, threads);
            for (step, (got, want)) in got.iter().zip(&want).enumerate() {
                assert_eq!(
                    got, want,
                    "{name} on {threads} thread(s): the hash after step {step} is not the recorded one"
                );
            }
            assert_eq!(got.len(), want.len(), "{name} on {threads} thread(s): ran {} steps", got.len());
            assert_eq!(failed.as_ref().map(|f| f.0), error, "{name} on {threads} thread(s): stopped at {failed:?}");
            if let (Some((_, got)), Some(want)) = (&failed, message) {
                assert!(
                    got.contains(want),
                    "{name} on {threads} thread(s): the engine says {got:?}, recorded {want:?}"
                );
            }
        }
    }
}

#[test]
fn the_records_are_written_as_the_generator_writes_them() {
    // The generator's own first lines, as it writes them (tools/gen_random_models.py).
    assert_eq!(records_csv(4), "id,weight,ci,cf,cb\n0,1,-11,-10.00,1\n1,2,-1,9.16,0\n2,3,9,8.31,0\n3,4,-4,7.46,1\n");
}
