//! Stage S10.8: the parts of a record formula that are the same for every record are
//! computed once (docs/S10-PLAN.md). The values must be what plain evaluation gives, and a
//! national part that fails must stop the run at the same step, naming the same variable.

use std::sync::Arc;

use polisim_core::{Col, RunConfig, Simulation, Val, load_model};

const MODEL: &str = r#"
[model]
id = "hoisting"
format = 1
currency = "GBP"
minor_units = 100
step = "month"
phases = ["one"]

[entity.rec]
data = "rec.csv"
id = "id"
weight = "weight"

[entity.rec.columns.ci]
type = "int"
unit = "1"

[param.zero]
type = "real"
unit = "1"
value = 0.0

[param.rate]
type = "real"
unit = "1"
value = 0.25

[state.tick]
type = "int"
unit = "1"
phase = "one"
initial = 0
next = "tick + 1"

[var.scaled]
type = "int"
unit = "1"
entity = "rec"
phase = "one"
expr = "ci * 2 + round(rate * 400.0 * (tick + 1)) - div(ci, 3)"

[var.total]
type = "int"
unit = "rec"
phase = "one"
expr = "wsum(rec, scaled + round(rate * 4.0))"
"#;

fn simulation(extra: &str) -> Result<Simulation, String> {
    let dir = std::env::temp_dir().join(format!("polisim-hoisting-{}-{}", std::process::id(), extra.len()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("model.toml"), format!("{MODEL}\n{extra}")).unwrap();
    std::fs::write(dir.join("rec.csv"), "id,weight,ci\n0,1,5\n1,2,3\n2,1,7\n").unwrap();
    let model = load_model(&dir).map_err(|e| e.to_string());
    let _ = std::fs::remove_dir_all(&dir);
    Simulation::new(Arc::new(model?), RunConfig::default()).map_err(|e| e.to_string())
}

#[test]
fn national_parts_give_the_plain_values() {
    let mut sim = simulation("").unwrap();
    // As plain evaluation gives them: tick is 0, 1, 2 when read in its own phase.
    for (step, want) in [[109, 105, 112], [209, 205, 212], [309, 305, 312]].iter().enumerate() {
        sim.step().unwrap();
        assert_eq!(sim.column("scaled"), Some(&Col::I(want.to_vec())), "step {step}");
        let total = want[0] + 2 * want[1] + want[2] + 4;
        assert_eq!(sim.scalar("total"), Some(Val::I(total)), "step {step}");
    }
}

#[test]
fn a_national_part_that_fails_stops_the_run_as_before() {
    // round(1.0 / (zero * tick)) is the same for every record and fails at once; the
    // record part div(ci, ci - 3) fails for the second record. The run stops in step 0,
    // naming the variable, as before (the contract names the step and the
    // variable; which of a formula's failures is described may differ).
    let extra = "[var.fragile]\ntype = \"int\"\nunit = \"1\"\nentity = \"rec\"\nphase = \"one\"\n\
                 expr = \"div(ci, ci - 3) + round(1.0 / (zero * tick))\"\n";
    let mut sim = simulation(extra).unwrap();
    let error = sim.step().unwrap_err().to_string();
    assert!(error.contains("step 0") && error.contains("fragile"), "{error}");
    // The national part alone, with every record's part fine: the same.
    let extra = "[var.fragile]\ntype = \"int\"\nunit = \"1\"\nentity = \"rec\"\nphase = \"one\"\n\
                 expr = \"ci + round(1.0 / (zero * tick))\"\n";
    let mut sim = simulation(extra).unwrap();
    let error = sim.step().unwrap_err().to_string();
    assert!(error.contains("step 0") && error.contains("fragile") && error.contains("whole number"), "{error}");
}
