//! Every line of conformance/cases.tsv must evaluate to what the oracle recorded:
//! the same value bit for bit, or the same kind of refusal.

use std::path::PathBuf;
use std::sync::Arc;

use polisim_core::{Col, Computed, Error, RunConfig, Simulation, Ty, Val, load_model};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn real(v: f64) -> String {
    if v.is_nan() { "nan".to_string() } else { format!("{:016x}", v.to_bits()) }
}

fn encode(value: Computed) -> String {
    let flag = |b: bool| if b { "T".to_string() } else { "F".to_string() };
    match value {
        Computed::One(Val::I(v)) => v.to_string(),
        Computed::One(Val::F(v)) => real(v),
        Computed::One(Val::B(v)) => flag(v),
        Computed::Each(Col::I(c)) => c.iter().map(i64::to_string).collect::<Vec<_>>().join(","),
        Computed::Each(Col::F(c)) => c.iter().map(|v| real(*v)).collect::<Vec<_>>().join(","),
        Computed::Each(Col::B(c)) => c.iter().map(|v| flag(*v)).collect::<Vec<_>>().join(","),
    }
}

#[test]
fn engine_reproduces_every_recorded_case() {
    // Seed and warm-up steps are those of tools/gen_conformance.py.
    let model = Arc::new(load_model(&root().join("conformance/model")).unwrap());
    let config = RunConfig { seed: 20261114, preset: "central".to_string(), ..Default::default() };
    let mut sim = Simulation::new(model, config).unwrap();
    for _ in 0..3 {
        sim.step().unwrap();
    }

    let text = std::fs::read_to_string(root().join("conformance/cases.tsv")).unwrap();
    let mut lines: Vec<&str> = text.split('\n').collect();
    assert_eq!(lines.pop(), Some(""));
    assert!(lines.len() > 3000);
    let mut mismatches = Vec::new();
    for (number, line) in lines.iter().enumerate() {
        let fields: Vec<&str> = line.split('\t').collect();
        assert_eq!(fields.len(), 5, "line {}", number + 1);
        let (ctx, ty, unit, formula, want) = (fields[0], fields[1], fields[2], fields[3], fields[4]);
        let ty = match ty {
            "int" => Ty::Int,
            "real" => Ty::Real,
            _ => Ty::Bool,
        };
        let got = match sim.evaluate(formula, if ctx == "-" { None } else { Some(ctx) }, ty, unit) {
            Ok(value) => encode(value),
            Err(Error::Formula(_)) => "E:static".to_string(),
            Err(Error::Sim(_)) => "E:runtime".to_string(),
            Err(Error::Model(message)) => format!("E:model {message}"),
        };
        if got != want {
            mismatches.push(format!("line {}: {formula:?}\n    oracle {want}\n    engine {got}", number + 1));
        }
    }
    assert!(
        mismatches.is_empty(),
        "{} of {} cases differ:\n{}",
        mismatches.len(),
        lines.len(),
        mismatches[..mismatches.len().min(12)].join("\n")
    );
}
